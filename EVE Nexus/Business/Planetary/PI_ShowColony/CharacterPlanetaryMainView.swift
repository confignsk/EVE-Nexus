import SwiftUI

// 行星信息模型
struct PlanetTypeInfo {
    let name: String
    let icon: String
}

// 最终产品模型
struct FinalProduct: Identifiable {
    let id: Int // typeId
    let typeId: Int
    let icon: String
}

@MainActor
final class CharacterPlanetaryViewModel: ObservableObject {
    @Published private(set) var planets: [CharacterPlanetaryInfo] = []
    @Published private(set) var planetNames: [Int: String] = [:]
    @Published private(set) var planetTypeInfo: [Int: PlanetTypeInfo] = [:]
    @Published private(set) var systemSecurities: [Int: Double] = [:] // 星系安等信息 [systemId: security]
    @Published private(set) var earliestExtractorExpiry: [Int: Date] = [:] // 每个行星的最早采集器过期时间 [planetId: Date]
    @Published private(set) var finalProducts: [Int: [FinalProduct]] = [:] // 每个行星的最终产品 [planetId: [FinalProduct]]
    @Published private(set) var loadingPlanets: Set<Int> = [] // 正在加载的行星ID集合
    @Published var isLoading = true
    @Published var errorMessage: String?

    private var loadingTask: Task<Void, Never>?
    private var expiryLoadingTask: Task<Void, Never>?
    private let characterId: Int?
    private var initialLoadDone = false

    init(characterId: Int?) {
        self.characterId = characterId

        // 在初始化时立即开始加载数据
        loadingTask = Task {
            await loadPlanets()
        }
    }

    deinit {
        loadingTask?.cancel()
        expiryLoadingTask?.cancel()
    }

    private func loadPlanetTypeInfo() async throws -> [Int: PlanetTypeInfo] {
        let typeIds = Array(PlanetaryUtils.planetTypeToColumn.keys).sorted()
        let typeIdsString = typeIds.map { String($0) }.joined(separator: ",")

        var tempPlanetTypeInfo: [Int: PlanetTypeInfo] = [:]

        // 从数据库获取行星类型信息
        let typeQuery =
            "SELECT type_id, name, icon_filename FROM types WHERE type_id IN (\(typeIdsString))"
        if case let .success(rows) = DatabaseManager.shared.executeQuery(typeQuery) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let iconFilename = row["icon_filename"] as? String
                {
                    tempPlanetTypeInfo[typeId] = PlanetTypeInfo(
                        name: name, icon: iconFilename
                    )
                }
            }
        }

        return tempPlanetTypeInfo
    }

    func loadPlanets(forceRefresh: Bool = false) async {
        // 如果已经加载过且不是强制刷新，则跳过
        if initialLoadDone, !forceRefresh {
            return
        }

        // 取消之前的加载任务
        loadingTask?.cancel()

        // 创建新的加载任务
        loadingTask = Task {
            isLoading = true
            errorMessage = nil

            do {
                // 首先加载行星类型信息（静态数据）
                let planetTypeInfo = try await loadPlanetTypeInfo()

                if let characterId = characterId {
                    // 获取行星信息（动态数据）
                    let planetsList = try await CharacterPlanetaryAPI.fetchCharacterPlanetary(
                        characterId: characterId, forceRefresh: forceRefresh
                    )

                    if Task.isCancelled { return }

                    // 获取所有行星ID
                    let planetIds = planetsList.map { $0.planetId }
                    let planetIdsString = planetIds.sorted().map { String($0) }.joined(
                        separator: ",")

                    if Task.isCancelled { return }

                    var tempPlanetNames: [Int: String] = [:]
                    var tempSystemSecurities: [Int: Double] = [:]

                    // 获取所有唯一的星系ID
                    let uniqueSystemIds = Array(Set(planetsList.map { $0.solarSystemId }))
                    if !uniqueSystemIds.isEmpty {
                        let systemIdsString = uniqueSystemIds.sorted().map { String($0) }.joined(separator: ",")

                        // 批量获取星系安等信息
                        let securityQuery = """
                            SELECT u.solarsystem_id, u.system_security
                            FROM universe u
                            WHERE u.solarsystem_id IN (\(systemIdsString))
                        """
                        if case let .success(rows) = DatabaseManager.shared.executeQuery(securityQuery) {
                            for row in rows {
                                if let systemId = row["solarsystem_id"] as? Int,
                                   let security = row["system_security"] as? Double
                                {
                                    tempSystemSecurities[systemId] = security
                                }
                            }
                        }
                    }

                    // 获取行星名称
                    let nameQuery =
                        "SELECT itemID, itemName FROM celestialNames WHERE itemID IN (\(planetIdsString))"
                    if case let .success(rows) = DatabaseManager.shared.executeQuery(nameQuery) {
                        for row in rows {
                            if let itemId = row["itemID"] as? Int,
                               let itemName = row["itemName"] as? String
                            {
                                tempPlanetNames[itemId] = itemName
                            }
                        }
                    }

                    if Task.isCancelled { return }

                    await MainActor.run {
                        self.planets = planetsList
                        self.planetNames = tempPlanetNames
                        self.planetTypeInfo = planetTypeInfo
                        self.systemSecurities = tempSystemSecurities
                        self.isLoading = false
                        self.initialLoadDone = true
                    }

                    // 异步加载所有行星的采集器过期时间（最多6线程）
                    await loadExtractorExpiryTimes(characterId: characterId, planets: planetsList)
                } else {
                    // 如果没有选择角色，只加载静态数据
                    await MainActor.run {
                        self.planets = []
                        self.planetNames = [:]
                        self.planetTypeInfo = planetTypeInfo
                        self.systemSecurities = [:]
                        self.isLoading = false
                        self.initialLoadDone = true
                    }
                }
            } catch {
                Logger.error("加载行星数据失败: \(error.localizedDescription)")
                if !Task.isCancelled {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                        self.isLoading = false
                    }
                }
            }
        }

        // 等待任务完成
        await loadingTask?.value
    }

    func getPlanetTypeInfo(for planetType: String) -> PlanetTypeInfo? {
        // 通过columnToPlanetType找到对应的行星类型ID
        if let typeId = PlanetaryUtils.columnToPlanetType[planetType],
           let info = planetTypeInfo[typeId]
        {
            return info
        }
        return nil
    }

    func getPlanetName(for planetId: Int) -> String {
        return planetNames[planetId]
            ?? NSLocalizedString("Main_Planetary_Unknown_Planet", comment: "")
    }

    func getSystemSecurity(for systemId: Int) -> Double? {
        return systemSecurities[systemId]
    }

    func getEarliestExtractorExpiry(for planetId: Int) -> Date? {
        return earliestExtractorExpiry[planetId]
    }

    func getFinalProducts(for planetId: Int) -> [FinalProduct] {
        return finalProducts[planetId] ?? []
    }

    func isLoadingPlanetDetail(for planetId: Int) -> Bool {
        return loadingPlanets.contains(planetId)
    }

    /// 异步加载所有行星的采集器过期时间，最多6个并发线程
    private func loadExtractorExpiryTimes(characterId: Int, planets: [CharacterPlanetaryInfo]) async {
        // 取消之前的任务
        expiryLoadingTask?.cancel()

        // 清理之前的加载状态
        await MainActor.run {
            self.loadingPlanets.removeAll()
        }

        expiryLoadingTask = Task {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime]

            // 初始化加载状态：将所有行星标记为正在加载
            await MainActor.run {
                self.loadingPlanets = Set(planets.map { $0.planetId })
            }

            // 使用 Actor 来限制并发数
            let limiter = ConcurrencyLimiter(maxConcurrent: 6)

            await withTaskGroup(of: (Int, Date?, [FinalProduct]).self) { group in
                for planet in planets {
                    if Task.isCancelled { break }

                    group.addTask {
                        await limiter.waitForSlot()
                        defer {
                            Task {
                                await limiter.releaseSlot()
                            }
                        }

                        do {
                            // 获取行星详情
                            let detail = try await CharacterPlanetaryAPI.fetchPlanetaryDetail(
                                characterId: characterId,
                                planetId: planet.planetId,
                                forceRefresh: false
                            )

                            // 查找所有采集器的最早过期时间
                            var earliestExpiry: Date? = nil
                            let currentTime = Date()

                            for pin in detail.pins {
                                if let expiryTimeString = pin.expiryTime,
                                   let expiryTime = dateFormatter.date(from: expiryTimeString),
                                   expiryTime > currentTime
                                {
                                    if earliestExpiry == nil || expiryTime < earliestExpiry! {
                                        earliestExpiry = expiryTime
                                    }
                                }
                            }

                            // 计算最终产品：找出只输出，不输入到其他设施的资源
                            let finalProducts = self.calculateFinalProducts(detail: detail)

                            return (planet.planetId, earliestExpiry, finalProducts)
                        } catch {
                            Logger.warning("获取行星 \(planet.planetId) 的采集器过期时间失败: \(error.localizedDescription)")
                            return (planet.planetId, nil, [])
                        }
                    }
                }

                // 收集结果并更新UI
                var expiryResults: [Int: Date] = [:]
                var productResults: [Int: [FinalProduct]] = [:]
                var completedPlanetIds = Set<Int>()

                for await (planetId, expiry, products) in group {
                    completedPlanetIds.insert(planetId)
                    if let expiry = expiry {
                        expiryResults[planetId] = expiry
                    }
                    if !products.isEmpty {
                        productResults[planetId] = products
                    }
                }

                if !Task.isCancelled {
                    await MainActor.run {
                        self.earliestExtractorExpiry = expiryResults
                        self.finalProducts = productResults
                        // 从加载集合中移除已完成的行星
                        self.loadingPlanets.subtract(completedPlanetIds)
                    }
                }
            }
        }

        await expiryLoadingTask?.value
    }

    /// 计算最终产品：找出只输出，不输入到其他设施的资源
    /// 参考 RIFT：最终产品 = (生产的产品 + 采集的产品) - 消费的产品
    /// 即：所有被生产/采集的资源中，没有被工厂消费的资源就是最终产品
    private nonisolated func calculateFinalProducts(detail: PlanetaryDetail) -> [FinalProduct] {
        // 1. 获取所有生产的产品（工厂的输出）
        var producingTypeIds = Set<Int>()
        for pin in detail.pins {
            // 检查是否是工厂
            if let factoryDetails = pin.factoryDetails {
                let schematicId = factoryDetails.schematicId
                if let schematic = getSchematic(schematicId) {
                    producingTypeIds.insert(schematic.outputType.id)
                }
            } else if let schematicId = pin.schematicId {
                // 备用：直接从 pin 获取 schematicId
                if let schematic = getSchematic(schematicId) {
                    producingTypeIds.insert(schematic.outputType.id)
                }
            }
        }

        // 2. 获取所有采集的产品（采集器的输出）
        var extractingTypeIds = Set<Int>()
        for pin in detail.pins {
            if let extractorDetails = pin.extractorDetails,
               let productTypeId = extractorDetails.productTypeId
            {
                extractingTypeIds.insert(productTypeId)
            }
        }

        // 3. 合并生产和采集的产品
        let allProducedTypeIds = producingTypeIds.union(extractingTypeIds)

        // 4. 获取所有消费的产品（工厂的输入）
        var consumingTypeIds = Set<Int>()
        for pin in detail.pins {
            if let factoryDetails = pin.factoryDetails {
                let schematicId = factoryDetails.schematicId
                if let schematic = getSchematic(schematicId) {
                    for inputType in schematic.inputs.keys {
                        consumingTypeIds.insert(inputType.id)
                    }
                }
            } else if let schematicId = pin.schematicId {
                if let schematic = getSchematic(schematicId) {
                    for inputType in schematic.inputs.keys {
                        consumingTypeIds.insert(inputType.id)
                    }
                }
            }
        }

        // 5. 最终产品 = 生产/采集的产品 - 消费的产品
        let finalProductIds = allProducedTypeIds.subtracting(consumingTypeIds)

        // 从数据库获取这些资源的图标信息
        var finalProducts: [FinalProduct] = []
        if !finalProductIds.isEmpty {
            let typeIdsString = finalProductIds.sorted().map { String($0) }.joined(separator: ",")
            let query = "SELECT type_id, name, icon_filename FROM types WHERE type_id IN (\(typeIdsString))"
            if case let .success(rows) = DatabaseManager.shared.executeQuery(query) {
                for row in rows {
                    if let typeId = row["type_id"] as? Int,
                       let iconFilename = row["icon_filename"] as? String
                    {
                        let name = row["name"] as? String ?? "Unknown"
                        finalProducts.append(FinalProduct(id: typeId, typeId: typeId, icon: iconFilename))
                        Logger.info("最终产品: \(name) (typeId: \(typeId))")
                    }
                }
            }
        }

        // 按typeId排序，确保显示顺序一致
        finalProducts.sort { $0.typeId < $1.typeId }

        Logger.info("找到 \(finalProducts.count) 个最终产品: \(finalProducts.map { "\($0.typeId)" }.joined(separator: ", "))")

        return finalProducts
    }

    /// 从数据库获取配方信息
    private nonisolated func getSchematic(_ schematicId: Int) -> Schematic? {
        let query = """
            SELECT schematic_id, output_typeid, name, cycle_time, output_value, input_typeid, input_value
            FROM planetSchematics
            WHERE schematic_id = ?
        """

        guard case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: [schematicId]),
              let row = rows.first,
              let id = row["schematic_id"] as? Int,
              let outputTypeId = row["output_typeid"] as? Int,
              let cycleTime = row["cycle_time"] as? Int,
              let outputValue = row["output_value"] as? Int
        else {
            return nil
        }

        // 获取输出类型信息
        let outputTypeQuery = "SELECT type_id, name, volume FROM types WHERE type_id = ?"
        guard case let .success(outputRows) = DatabaseManager.shared.executeQuery(outputTypeQuery, parameters: [outputTypeId]),
              let outputRow = outputRows.first,
              let outputTypeIdFromDb = outputRow["type_id"] as? Int,
              let outputName = outputRow["name"] as? String,
              let outputVolume = outputRow["volume"] as? Double
        else {
            return nil
        }

        let outputType = Type(id: outputTypeIdFromDb, name: outputName, volume: outputVolume)

        // 解析输入类型ID和数量
        var inputs: [Type: Int64] = [:]
        if let inputTypeIdString = row["input_typeid"] as? String,
           let inputValueString = row["input_value"] as? String
        {
            let inputTypeIds = inputTypeIdString.components(separatedBy: ",").compactMap {
                Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let inputValues = inputValueString.components(separatedBy: ",").compactMap {
                Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            if inputTypeIds.count == inputValues.count {
                for i in 0 ..< inputTypeIds.count {
                    let typeId = inputTypeIds[i]
                    let quantity = inputValues[i]

                    let inputTypeQuery = "SELECT type_id, name, volume FROM types WHERE type_id = ?"
                    if case let .success(inputRows) = DatabaseManager.shared.executeQuery(inputTypeQuery, parameters: [typeId]),
                       let inputRow = inputRows.first,
                       let inputTypeIdFromDb = inputRow["type_id"] as? Int,
                       let inputName = inputRow["name"] as? String,
                       let inputVolume = inputRow["volume"] as? Double
                    {
                        let inputType = Type(id: inputTypeIdFromDb, name: inputName, volume: inputVolume)
                        inputs[inputType] = Int64(quantity)
                    }
                }
            }
        }

        return Schematic(
            id: id,
            cycleTime: TimeInterval(cycleTime),
            outputType: outputType,
            outputQuantity: Int64(outputValue),
            inputs: inputs
        )
    }
}

// 并发限制器 Actor
actor ConcurrencyLimiter {
    private var availableSlots: Int
    private var waitingTasks: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        availableSlots = maxConcurrent
    }

    func waitForSlot() async {
        if availableSlots > 0 {
            availableSlots -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waitingTasks.append(continuation)
        }
    }

    func releaseSlot() {
        if !waitingTasks.isEmpty {
            let next = waitingTasks.removeFirst()
            next.resume()
        } else {
            availableSlots += 1
        }
    }
}

// 用于存储选中星球信息的结构
struct SelectedPlanet {
    let characterId: Int
    let planetId: Int
    let planetName: String
}

struct CharacterPlanetaryView: View {
    let characterId: Int?
    @StateObject private var viewModel: CharacterPlanetaryViewModel
    @State private var selectedPlanet: SelectedPlanet?

    init(characterId: Int?) {
        self.characterId = characterId
        _viewModel = StateObject(
            wrappedValue: CharacterPlanetaryViewModel(characterId: characterId))
    }

    var body: some View {
        List {
            // 行星开发计算器功能
            Section(NSLocalizedString("Main_Planetary_calc", comment: "")) {
                NavigationLink {
                    PlanetarySiteFinder(characterId: characterId)
                } label: {
                    Text(NSLocalizedString("Main_Planetary_location_calc", comment: ""))
                }
                NavigationLink {
                    PIOutputCalculatorView(characterId: characterId)
                } label: {
                    Text(NSLocalizedString("Main_Planetary_Output", comment: ""))
                }
                NavigationLink {
                    PIAllInOneMainView(characterId: characterId)
                } label: {
                    Text(NSLocalizedString("Planet_All-in-One_Calc", comment: ""))
                }
                NavigationLink {
                    PIAllInOneSystemFinderMainView(characterId: characterId)
                } label: {
                    Text(
                        NSLocalizedString(
                            "AllInOne_SystemFinder_Title", comment: "查找 All-in-One 星系"
                        ))
                }
                NavigationLink {
                    PIProductionChainView(characterId: characterId)
                } label: {
                    Text(NSLocalizedString("PI_Chain_Title", comment: "生产链分析"))
                }
            }
            if viewModel.isLoading {
                Section(header: Text(NSLocalizedString("Main_Planetary_of_Mine", comment: ""))) {
                    HStack {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(.circular)
                        Spacer()
                    }
                }
            } else {
                if characterId != nil {
                    if viewModel.planets.isEmpty {
                        Section(
                            header: Text(NSLocalizedString("Main_Planetary_of_Mine", comment: ""))
                        ) {
                            NoDataSection()
                        }
                    } else {
                        Section(
                            header: Text(NSLocalizedString("Main_Planetary_of_Mine", comment: "")),
                            footer: Text(
                                String(
                                    format: NSLocalizedString(
                                        "Main_Planetary_Total_Count", comment: ""
                                    ),
                                    viewModel.planets.count
                                ))
                        ) {
                            ForEach(viewModel.planets, id: \.planetId) { planet in
                                Button {
                                    selectedPlanet = SelectedPlanet(
                                        characterId: characterId!,
                                        planetId: planet.planetId,
                                        planetName: viewModel.getPlanetName(for: planet.planetId)
                                    )
                                } label: {
                                    HStack {
                                        if let typeInfo = viewModel.getPlanetTypeInfo(
                                            for: planet.planetType)
                                        {
                                            Image(
                                                uiImage: IconManager.shared.loadUIImage(
                                                    for: typeInfo.icon)
                                            )
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 4) {
                                                // 显示星系安等（如果有）
                                                if let security = viewModel.getSystemSecurity(for: planet.solarSystemId) {
                                                    Text(formatSystemSecurity(security))
                                                        .foregroundColor(getSecurityColor(security))
                                                        .font(.system(.headline, design: .monospaced))
                                                }
                                                Text(viewModel.getPlanetName(for: planet.planetId))
                                                    .font(.headline)
                                                    .foregroundColor(.primary)
                                            }
                                            .contextMenu {
                                                let planetName = viewModel.getPlanetName(for: planet.planetId)
                                                Button {
                                                    UIPasteboard.general.string = planetName
                                                } label: {
                                                    Label(
                                                        NSLocalizedString("Misc_Copy_Name", comment: ""),
                                                        systemImage: "doc.on.doc"
                                                    )
                                                }
                                            }

                                            if let typeInfo = viewModel.getPlanetTypeInfo(
                                                for: planet.planetType)
                                            {
                                                Text(typeInfo.name)
                                                    .font(.subheadline)
                                                    .foregroundColor(.gray)
                                            } else {
                                                Text(
                                                    NSLocalizedString(
                                                        "Main_Planetary_Unknown_Type", comment: ""
                                                    )
                                                )
                                                .font(.subheadline)
                                                .foregroundColor(.gray)
                                            }

                                            // 显示采集器最早过期时间
                                            if let expiryDate = viewModel.getEarliestExtractorExpiry(for: planet.planetId) {
                                                let timeRemaining = expiryDate.timeIntervalSince(Date())
                                                if timeRemaining > 0 {
                                                    Text("\(NSLocalizedString("Planet_Detail_Extractor_Expiry_Time", comment: "")): \(formatTimeRemaining(timeRemaining))")
                                                        .font(.caption2)
                                                        .foregroundColor(timeRemaining < 1 * 24 * 3600 ? .red : .green)
                                                } else {
                                                    Text(NSLocalizedString("Planet_Detail_Extractor_Expired", comment: ""))
                                                        .font(.caption2)
                                                        .foregroundColor(.red)
                                                }
                                            }
                                        }

                                        Spacer()

                                        // 显示加载指示器或最终产品图标
                                        if viewModel.isLoadingPlanetDetail(for: planet.planetId) {
                                            ProgressView()
                                                .frame(width: 28, height: 28)
                                        } else {
                                            let products = viewModel.getFinalProducts(for: planet.planetId)
                                            if !products.isEmpty {
                                                FinalProductsGridView(products: products)
                                            }
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Planetary_Title", comment: ""))
        .refreshable {
            // 清理星球详情缓存，防止数据不同步
            if let characterId = characterId {
                CharacterPlanetaryAPI.clearPlanetDetailCache(characterId: characterId)
            }
            await viewModel.loadPlanets(forceRefresh: true)
        }
        .sheet(item: $selectedPlanet) { planet in
            NavigationStack {
                PlanetDetailView(
                    characterId: planet.characterId,
                    planetId: planet.planetId,
                    planetName: planet.planetName
                )
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            selectedPlanet = nil
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(.primary)
                                .frame(width: 30, height: 30)
                                .background(Color(.systemBackground))
                                .clipShape(Circle())
                        }
                    }
                }
            }
            .interactiveDismissDisabled()
        }
    }
}

// 让 SelectedPlanet 遵循 Identifiable 协议
extension SelectedPlanet: Identifiable {
    var id: Int { planetId }
}

// 最终产品图标网格视图
struct FinalProductsGridView: View {
    let products: [FinalProduct]

    var body: some View {
        let count = products.count
        let iconSize: CGFloat = count == 1 ? 28 : (count == 2 ? 20 : 16)
        let spacing: CGFloat = count == 1 ? 0 : 4

        VStack(spacing: spacing) {
            if count == 1 {
                // 1个：显示1个
                ProductIcon(product: products[0], size: iconSize)
            } else if count == 2 {
                // 2个：上下显示
                ProductIcon(product: products[0], size: iconSize)
                ProductIcon(product: products[1], size: iconSize)
            } else if count == 3 {
                // 3个：第一行2个，第二行1个
                HStack(spacing: spacing) {
                    ProductIcon(product: products[0], size: iconSize)
                    ProductIcon(product: products[1], size: iconSize)
                }
                HStack(spacing: spacing) {
                    ProductIcon(product: products[2], size: iconSize)
                    Spacer()
                }
            } else if count == 4 {
                // 4个：第一行2个，第二行2个
                HStack(spacing: spacing) {
                    ProductIcon(product: products[0], size: iconSize)
                    ProductIcon(product: products[1], size: iconSize)
                }
                HStack(spacing: spacing) {
                    ProductIcon(product: products[2], size: iconSize)
                    ProductIcon(product: products[3], size: iconSize)
                }
            } else if count == 5 {
                // 5个：第一行3个，第二行2个
                HStack(spacing: spacing) {
                    ProductIcon(product: products[0], size: iconSize)
                    ProductIcon(product: products[1], size: iconSize)
                    ProductIcon(product: products[2], size: iconSize)
                }
                HStack(spacing: spacing) {
                    ProductIcon(product: products[3], size: iconSize)
                    ProductIcon(product: products[4], size: iconSize)
                }
            } else {
                // 6个或更多：第一行3个，第二行3个（只显示前6个）
                HStack(spacing: spacing) {
                    ProductIcon(product: products[0], size: iconSize)
                    ProductIcon(product: products[1], size: iconSize)
                    ProductIcon(product: products[2], size: iconSize)
                }
                HStack(spacing: spacing) {
                    ProductIcon(product: products[3], size: iconSize)
                    ProductIcon(product: products[4], size: iconSize)
                    if products.count > 5 {
                        ProductIcon(product: products[5], size: iconSize)
                    }
                }
            }
        }
    }
}

// 产品图标视图
struct ProductIcon: View {
    let product: FinalProduct
    let size: CGFloat

    var body: some View {
        Image(uiImage: IconManager.shared.loadUIImage(for: product.icon))
            .resizable()
            .frame(width: size, height: size)
            .cornerRadius(4)
    }
}

// 格式化剩余时间显示
private func formatTimeRemaining(_ interval: TimeInterval) -> String {
    if interval < 0 {
        return ""
    }

    let totalSeconds = Int(interval)
    let days = totalSeconds / (24 * 3600)
    let hours = totalSeconds / 3600 % 24
    let minutes = totalSeconds / 60 % 60

    if days > 0 {
        if hours > 0 {
            return String(format: NSLocalizedString("Time_Days_Hours", comment: ""), days, hours)
        } else {
            return String(format: NSLocalizedString("Time_Days", comment: ""), days)
        }
    } else if hours > 0 {
        if minutes > 0 {
            return String(format: NSLocalizedString("Time_Hours_Minutes", comment: ""), hours, minutes)
        } else {
            return String(format: NSLocalizedString("Time_Hours", comment: ""), hours)
        }
    } else if minutes > 0 {
        return String(format: NSLocalizedString("Time_Minutes", comment: ""), minutes)
    } else {
        return NSLocalizedString("Time_Just_Now", comment: "刚刚")
    }
}

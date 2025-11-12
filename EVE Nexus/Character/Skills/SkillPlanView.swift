import Foundation
import SwiftUI

struct SkillPlan: Identifiable {
    let id: UUID
    var name: String
    var skills: [PlannedSkill]
    var totalTrainingTime: TimeInterval
    var totalSkillPoints: Int
    var lastUpdated: Date
}

struct PlannedSkill: Identifiable {
    let id: UUID
    let skillID: Int
    let skillName: String
    let currentLevel: Int
    let targetLevel: Int
    var trainingTime: TimeInterval
    var requiredSP: Int
    var prerequisites: [PlannedSkill]
    var currentSkillPoints: Int?
    var isCompleted: Bool
}

struct SkillPlanData: Codable {
    let id: UUID? // 可选，用于支持旧版本文件
    let name: String
    let lastUpdated: Date
    var skills: [String] // 格式: "type_id:level"
}

class SkillPlanFileManager {
    static let shared = SkillPlanFileManager()

    private init() {
        createSkillPlansDirectory()
    }

    private var skillPlansDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("SkillPlans", isDirectory: true)
    }

    // UUID -> 文件URL的映射缓存
    private var planFileMapping: [UUID: URL] = [:]

    private func createSkillPlansDirectory() {
        do {
            try FileManager.default.createDirectory(
                at: skillPlansDirectory, withIntermediateDirectories: true
            )
        } catch {
            Logger.error("创建技能计划目录失败: \(error)")
        }
    }

    func saveSkillPlan(characterId _: Int, plan: SkillPlan) {
        // 优先使用映射中的路径（保留原文件名格式）
        // 如果映射中没有，说明是新建的计划，使用新格式
        let fileURL: URL
        if let existingURL = planFileMapping[plan.id] {
            fileURL = existingURL
            Logger.debug("使用已有文件路径: \(fileURL.lastPathComponent)")
        } else {
            let fileName = "\(plan.id).json"
            fileURL = skillPlansDirectory.appendingPathComponent(fileName)
            // 新建文件时才更新映射
            planFileMapping[plan.id] = fileURL
            Logger.debug("创建新文件: \(fileName)")
        }

        // 检查文件是否存在，如果存在则读取当前内容进行对比
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let existingData = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601Full)
                let existingPlanData = try decoder.decode(SkillPlanData.self, from: existingData)

                // 创建新的计划数据，但保持原有的lastUpdated
                let newPlanData = SkillPlanData(
                    id: plan.id, // 包含 UUID
                    name: plan.name,
                    lastUpdated: existingPlanData.lastUpdated, // 保持原有的lastUpdated
                    skills: plan.skills.map { "\($0.skillID):\($0.targetLevel)" }
                )

                // 比较内容是否相同（除了lastUpdated）
                if existingPlanData.name == newPlanData.name,
                   Set(existingPlanData.skills) == Set(newPlanData.skills)
                {
                    Logger.debug("技能计划内容未变化，跳过保存: \(fileURL.lastPathComponent)")
                    return
                }
            } catch {
                Logger.error("读取现有技能计划失败: \(error)")
            }
        }

        // 如果文件不存在或内容有变化，则创建新的计划数据并保存
        let planData = SkillPlanData(
            id: plan.id, // 包含 UUID
            name: plan.name,
            lastUpdated: Date(), // 只有在内容真正变化时才更新时间
            skills: plan.skills.map { "\($0.skillID):\($0.targetLevel)" }
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .formatted(DateFormatter.iso8601Full)
            let data = try encoder.encode(planData)
            try data.write(to: fileURL)
            Logger.debug("保存技能计划成功: \(fileURL.lastPathComponent)")
        } catch {
            Logger.error("保存技能计划失败: \(fileURL.lastPathComponent) - \(error)")
        }
    }

    func loadSkillPlans(
        characterId: Int, databaseManager: DatabaseManager,
        learnedSkills _: [Int: CharacterSkill] = [:]
    ) -> [SkillPlan] {
        let fileManager = FileManager.default

        // 清空之前的映射
        planFileMapping.removeAll()

        // 创建技能队列修正器
        let corrector = SkillQueueCorrector(databaseManager: databaseManager)

        do {
            Logger.debug("开始加载技能计划，角色ID: \(characterId)")
            let files = try fileManager.contentsOfDirectory(
                at: skillPlansDirectory, includingPropertiesForKeys: nil
            )
            Logger.debug("找到文件数量: \(files.count)")

            // 预处理：迁移和清理旧文件
            preprocessFiles(files)

            // 预处理后重新扫描目录，获取迁移后的新文件
            let updatedFiles = try fileManager.contentsOfDirectory(
                at: skillPlansDirectory, includingPropertiesForKeys: nil
            )
            Logger.debug("预处理后文件数量: \(updatedFiles.count)")

            let plans = updatedFiles.filter { url in
                url.pathExtension == "json"
            }.compactMap { url -> SkillPlan? in
                do {
                    Logger.debug("尝试解析文件: \(url.lastPathComponent)")
                    let data = try Data(contentsOf: url)

                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601Full)
                    let planData = try decoder.decode(SkillPlanData.self, from: data)

                    // 从文件内容中读取 UUID（预处理后所有文件都应该有 UUID）
                    guard let validPlanId = planData.id else {
                        Logger.error("文件缺少 UUID（预处理可能失败）: \(url.lastPathComponent)")
                        try? FileManager.default.removeItem(at: url)
                        return nil
                    }

                    Logger.debug("从文件内容中读取 UUID: \(validPlanId)")

                    // 建立UUID到文件URL的映射
                    self.planFileMapping[validPlanId] = url
                    Logger.debug("建立文件映射: \(validPlanId) -> \(url.lastPathComponent)")

                    // 1. 将技能字符串转换为 (skillId, level) 列表
                    let parsedSkills = planData.skills.compactMap { skillString -> (skillId: Int, level: Int)? in
                        let components = skillString.split(separator: ":")
                        guard components.count == 2,
                              let typeId = Int(components[0]),
                              let level = Int(components[1])
                        else {
                            return nil
                        }
                        return (skillId: typeId, level: level)
                    }

                    // 2. 使用修正函数补齐前置依赖并去重
                    Logger.debug("[加载文件] 修正前技能数量: \(parsedSkills.count)")
                    let correctedSkills = corrector.correctSkillQueue(inputSkills: parsedSkills)
                    Logger.debug("[加载文件] 修正后技能数量: \(correctedSkills.count)")

                    // 3. 如果修正后的技能数量与原数量不同，需要更新文件
                    if correctedSkills.count != parsedSkills.count {
                        Logger.debug("[加载文件] 技能队列已修正，将更新文件")
                        let correctedSkillStrings = correctedSkills.map { "\($0.skillId):\($0.level)" }
                        let updatedPlanData = SkillPlanData(
                            id: validPlanId,
                            name: planData.name,
                            lastUpdated: Date(), // 更新时间
                            skills: correctedSkillStrings
                        )

                        // 保存修正后的文件
                        do {
                            let encoder = JSONEncoder()
                            encoder.dateEncodingStrategy = .formatted(DateFormatter.iso8601Full)
                            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                            let updatedData = try encoder.encode(updatedPlanData)
                            try updatedData.write(to: url)
                            Logger.debug("[加载文件] 已保存修正后的技能计划到文件")
                        } catch {
                            Logger.error("[加载文件] 保存修正后的文件失败: \(error)")
                        }
                    }

                    // 4. 创建技能对象（使用修正后的技能列表）
                    let skills = correctedSkills.map { skill -> PlannedSkill in
                        PlannedSkill(
                            id: UUID(),
                            skillID: skill.skillId,
                            skillName: "Unknown Skill (\(skill.skillId))", // 使用临时名称
                            currentLevel: 0, // 使用默认值
                            targetLevel: skill.level,
                            trainingTime: 0,
                            requiredSP: 0,
                            prerequisites: [],
                            currentSkillPoints: nil,
                            isCompleted: false
                        )
                    }

                    let plan = SkillPlan(
                        id: validPlanId,
                        name: planData.name,
                        skills: skills,
                        totalTrainingTime: 0,
                        totalSkillPoints: 0,
                        lastUpdated: planData.lastUpdated
                    )

                    Logger.debug("成功创建技能计划对象: \(plan.name)")
                    return plan

                } catch {
                    Logger.error("读取技能计划失败: \(error.localizedDescription)")
                    if let decodingError = error as? DecodingError {
                        switch decodingError {
                        case let .dataCorrupted(context):
                            Logger.error("数据损坏: \(context.debugDescription)")
                        case let .keyNotFound(key, context):
                            Logger.error("未找到键: \(key.stringValue), 路径: \(context.codingPath)")
                        case let .typeMismatch(type, context):
                            Logger.error("类型不匹配: 期望 \(type), 路径: \(context.codingPath)")
                        case let .valueNotFound(type, context):
                            Logger.error("值未找到: 类型 \(type), 路径: \(context.codingPath)")
                        @unknown default:
                            Logger.error("未知解码错误: \(decodingError)")
                        }
                    }
                    try? FileManager.default.removeItem(at: url)
                    return nil
                }
            }
            .sorted { $0.lastUpdated > $1.lastUpdated }

            Logger.debug("成功加载技能计划数量: \(plans.count)")
            return plans

        } catch {
            Logger.error("读取技能计划目录失败: \(error.localizedDescription)")
            return []
        }
    }

    func deleteSkillPlan(characterId _: Int, plan: SkillPlan) {
        // 从映射中获取文件URL
        guard let fileURL = planFileMapping[plan.id] else {
            Logger.error("映射中未找到技能计划: \(plan.name) (ID: \(plan.id)) - 这不应该发生！")
            return
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
            Logger.debug("删除技能计划成功: \(fileURL.lastPathComponent)")
            // 从映射中移除
            planFileMapping.removeValue(forKey: plan.id)
        } catch {
            Logger.error("删除技能计划失败: \(fileURL.lastPathComponent) - \(error)")
            // 即使删除失败也从映射中移除，避免映射与实际文件不一致
            planFileMapping.removeValue(forKey: plan.id)
        }
    }

    // 预处理文件：迁移旧格式文件，删除无效文件
    private func preprocessFiles(_ files: [URL]) {
        Logger.debug("[预处理] 开始检查和迁移文件")

        let jsonFiles = files.filter { $0.pathExtension == "json" }
        var filesToMigrate: [URL] = []
        var filesToDelete: [URL] = []

        // 第一轮：尝试按新格式解析（必须有 UUID）
        for url in jsonFiles {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601Full)
                let planData = try decoder.decode(SkillPlanData.self, from: data)

                if planData.id != nil {
                    // 新格式文件，跳过
                    Logger.debug("[预处理] ✅ 新格式文件: \(url.lastPathComponent)")
                } else {
                    // 文件可以解析，但没有 UUID，需要迁移
                    filesToMigrate.append(url)
                    Logger.debug("[预处理] 🔄 需要迁移: \(url.lastPathComponent)")
                }
            } catch {
                // 无法解析为新格式，可能是旧格式或损坏的文件
                filesToMigrate.append(url)
                Logger.debug("[预处理] 🔄 需要尝试迁移: \(url.lastPathComponent)")
            }
        }

        // 第二轮：迁移或删除
        for url in filesToMigrate {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601Full)

                // 定义旧格式的 SkillPlanData（UUID 可选）
                struct OldSkillPlanData: Codable {
                    let name: String
                    let lastUpdated: Date
                    var skills: [String]
                }

                let oldPlanData = try decoder.decode(OldSkillPlanData.self, from: data)

                // 成功解析旧格式，生成新 UUID 并保存为新文件
                let newUUID = UUID()
                let newPlanData = SkillPlanData(
                    id: newUUID,
                    name: oldPlanData.name,
                    lastUpdated: oldPlanData.lastUpdated,
                    skills: oldPlanData.skills
                )

                // 保存为新格式文件
                let newFileName = "\(newUUID).json"
                let newFileURL = skillPlansDirectory.appendingPathComponent(newFileName)

                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(DateFormatter.iso8601Full)
                let newData = try encoder.encode(newPlanData)
                try newData.write(to: newFileURL)

                Logger.debug("[预处理] ✅ 迁移成功: \(url.lastPathComponent) → \(newFileName)")

                // 删除旧文件
                try FileManager.default.removeItem(at: url)
                Logger.debug("[预处理] 🗑️ 删除旧文件: \(url.lastPathComponent)")

            } catch {
                // 无法解析，删除损坏的文件
                filesToDelete.append(url)
                Logger.error("[预处理] ❌ 无法解析，将删除: \(url.lastPathComponent) - \(error)")
            }
        }

        // 第三轮：删除无效文件
        for url in filesToDelete {
            do {
                try FileManager.default.removeItem(at: url)
                Logger.debug("[预处理] 🗑️ 删除无效文件: \(url.lastPathComponent)")
            } catch {
                Logger.error("[预处理] ❌ 删除失败: \(url.lastPathComponent) - \(error)")
            }
        }

        if !filesToMigrate.isEmpty || !filesToDelete.isEmpty {
            Logger.debug("[预处理] 完成 - 迁移: \(filesToMigrate.count - filesToDelete.count), 删除: \(filesToDelete.count)")
        } else {
            Logger.debug("[预处理] 无需处理的文件")
        }
    }
}

struct SkillPlanView: View {
    let characterId: Int
    @ObservedObject var databaseManager: DatabaseManager
    @State private var skillPlans: [SkillPlan] = []
    @State private var isShowingAddAlert = false
    @State private var newPlanName = ""
    @State private var searchText = ""
    @State private var learnedSkills: [Int: CharacterSkill] = [:] // 添加已学习技能的状态变量
    @State private var isShowingRenameAlert = false
    @State private var renamePlan: SkillPlan?
    @State private var renamePlanName = ""

    // 添加过滤后的计划列表计算属性
    private var filteredPlans: [SkillPlan] {
        if searchText.isEmpty {
            return skillPlans
        } else {
            return skillPlans.filter { plan in
                plan.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        List {
            if filteredPlans.isEmpty {
                if searchText.isEmpty {
                    Text(NSLocalizedString("Main_Skills_Plan_Empty", comment: ""))
                        .foregroundColor(.secondary)
                } else {
                    Text(String(format: NSLocalizedString("Main_EVE_Mail_No_Results", comment: "")))
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(filteredPlans) { plan in
                    NavigationLink {
                        SkillPlanDetailView(
                            plan: plan,
                            characterId: characterId,
                            databaseManager: databaseManager,
                            skillPlans: $skillPlans
                        )
                    } label: {
                        planRowView(plan)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            if let index = skillPlans.firstIndex(where: { $0.id == plan.id }) {
                                deletePlan(at: IndexSet(integer: index))
                            }
                        } label: {
                            Label(NSLocalizedString("Misc_Delete", comment: ""), systemImage: "trash")
                        }

                        Button {
                            renamePlan = plan
                            renamePlanName = plan.name
                            isShowingRenameAlert = true
                        } label: {
                            Label(NSLocalizedString("Misc_Rename", comment: ""), systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            renamePlan = plan
                            renamePlanName = plan.name
                            isShowingRenameAlert = true
                        } label: {
                            Label(NSLocalizedString("Misc_Rename", comment: ""), systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            if let index = skillPlans.firstIndex(where: { $0.id == plan.id }) {
                                deletePlan(at: IndexSet(integer: index))
                            }
                        } label: {
                            Label(NSLocalizedString("Misc_Delete", comment: ""), systemImage: "trash")
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .navigationTitle(NSLocalizedString("Main_Skills_Plan", comment: ""))
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Database_Search", comment: "")
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    newPlanName = ""
                    isShowingAddAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert(
            NSLocalizedString("Main_Skills_Plan_Add", comment: ""), isPresented: $isShowingAddAlert
        ) {
            TextField(NSLocalizedString("Main_Skills_Plan_Name", comment: ""), text: $newPlanName)

            Button(NSLocalizedString("Main_Skills_Plan_Add", comment: "")) {
                if !newPlanName.isEmpty {
                    let newPlan = SkillPlan(
                        id: UUID(),
                        name: newPlanName,
                        skills: [],
                        totalTrainingTime: 0,
                        totalSkillPoints: 0,
                        lastUpdated: Date()
                    )
                    skillPlans.append(newPlan)
                    SkillPlanFileManager.shared.saveSkillPlan(
                        characterId: characterId, plan: newPlan
                    )
                    newPlanName = ""
                }
            }
            .disabled(newPlanName.isEmpty)

            Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                newPlanName = ""
            }
        } message: {
            Text(NSLocalizedString("Main_Skills_Plan_Name", comment: ""))
        }
        .alert(NSLocalizedString("Misc_Rename", comment: ""), isPresented: $isShowingRenameAlert) {
            TextField(NSLocalizedString("Misc_Name", comment: ""), text: $renamePlanName)

            Button(NSLocalizedString("Misc_Done", comment: "")) {
                if let plan = renamePlan, !renamePlanName.isEmpty {
                    if let index = skillPlans.firstIndex(where: { $0.id == plan.id }) {
                        skillPlans[index].name = renamePlanName
                        SkillPlanFileManager.shared.saveSkillPlan(
                            characterId: characterId,
                            plan: skillPlans[index]
                        )
                    }
                }
                renamePlan = nil
                renamePlanName = ""
            }
            .disabled(renamePlanName.isEmpty)

            Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                renamePlan = nil
                renamePlanName = ""
            }
        }
        .task {
            // 先加载角色已学习的技能
            await loadLearnedSkills()
            // 然后加载已保存的技能计划
            skillPlans = SkillPlanFileManager.shared.loadSkillPlans(
                characterId: characterId,
                databaseManager: databaseManager,
                learnedSkills: learnedSkills // 传入已学习的技能
            )
        }
    }

    private func planRowView(_ plan: SkillPlan) -> some View {
        HStack(alignment: .center, spacing: 8) {
            // 左侧：计划名称和更新时间
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(formatDate(plan.lastUpdated))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 右侧：技能数量和训练时间
            VStack(alignment: .trailing, spacing: 4) {
                Text(
                    String(
                        format: "%d %@", plan.skills.count,
                        NSLocalizedString("Main_Skills_Plan_Skills", comment: "")
                    )
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents(
            [.minute, .hour, .day], from: date, to: now
        )

        if let days = components.day {
            if days > 30 {
                // 超过30天显示具体日期
                let formatter = DateFormatter()
                formatter.dateFormat = NSLocalizedString("Date_Format_Month_Day", comment: "")
                return formatter.string(from: date)
            } else if days > 0 {
                return String(format: NSLocalizedString("Time_Days_Ago", comment: ""), days)
            }
        }

        if let hours = components.hour, hours > 0 {
            return String(format: NSLocalizedString("Time_Hours_Ago", comment: ""), hours)
        } else if let minutes = components.minute, minutes > 0 {
            return String(format: NSLocalizedString("Time_Minutes_Ago", comment: ""), minutes)
        } else {
            return NSLocalizedString("Time_Just_Now", comment: "")
        }
    }

    private func deletePlan(at offsets: IndexSet) {
        let planIdsToDelete = offsets.map { filteredPlans[$0].id }
        skillPlans.removeAll { plan in
            if planIdsToDelete.contains(plan.id) {
                SkillPlanFileManager.shared.deleteSkillPlan(characterId: characterId, plan: plan)
                return true
            }
            return false
        }
    }

    // 添加加载已学习技能的方法
    private func loadLearnedSkills() async {
        do {
            // 调用API获取技能数据
            let skillsResponse = try await CharacterSkillsAPI.shared.fetchCharacterSkills(
                characterId: characterId,
                forceRefresh: false
            )

            // 创建技能ID到技能信息的映射
            learnedSkills = Dictionary(
                uniqueKeysWithValues: skillsResponse.skills.map { ($0.skill_id, $0) })
            Logger.debug("成功加载角色技能数量: \(learnedSkills.count)")
        } catch {
            Logger.error("获取技能数据失败: \(error)")
        }
    }
}

extension DateFormatter {
    static let iso8601Full: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

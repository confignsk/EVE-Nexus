import Foundation

/// 技能计划辅助类 - 处理技能添加的共享逻辑
class SkillPlanHelper {
    // 添加技能及其所有前置依赖
    static func collectSkillsToAdd(
        skillId: Int,
        skillName: String,
        targetLevel: Int,
        databaseManager: DatabaseManager,
        currentSkillLevels: [Int: Int],
        addedSkills: inout Set<Int>,
        skillLevels: inout [Int: Int]
    ) -> [(skillId: Int, skillName: String, level: Int)] {
        Logger.debug("[+] 开始添加技能到计划 - 技能: \(skillName) (ID: \(skillId)), 等级: \(targetLevel)")

        let currentTargetLevel = currentSkillLevels[skillId] ?? 0

        // 收集要添加的所有技能（用于批量添加）
        var skillsToAdd: [(skillId: Int, skillName: String, level: Int)] = []

        // 只在技能从0级添加时检查前置依赖
        if !addedSkills.contains(skillId) {
            Logger.debug("[+] 技能未添加，检查前置技能依赖")

            // 获取所有前置技能
            let prerequisites = getAllPrerequisites(
                skillId: skillId,
                requiredLevel: targetLevel,
                databaseManager: databaseManager
            )

            // 收集前置技能
            for prereq in prerequisites {
                let currentLevel = currentSkillLevels[prereq.skillId] ?? 0
                let requiredLevel = prereq.requiredLevel

                if !addedSkills.contains(prereq.skillId) {
                    let prereqSkillName = getSkillName(skillId: prereq.skillId, databaseManager: databaseManager)
                    skillsToAdd.append((skillId: prereq.skillId, skillName: prereqSkillName, level: requiredLevel))
                    addedSkills.insert(prereq.skillId)
                    skillLevels[prereq.skillId] = requiredLevel
                } else if currentLevel < requiredLevel {
                    let prereqSkillName = getSkillName(skillId: prereq.skillId, databaseManager: databaseManager)
                    skillsToAdd.append((skillId: prereq.skillId, skillName: prereqSkillName, level: requiredLevel))
                    skillLevels[prereq.skillId] = requiredLevel
                }
            }

            // 收集目标技能所有等级
            for currentLevel in 1 ... targetLevel {
                skillsToAdd.append((skillId: skillId, skillName: skillName, level: currentLevel))
            }
            addedSkills.insert(skillId)
            skillLevels[skillId] = targetLevel
        } else if currentTargetLevel < targetLevel {
            // 升级技能
            for currentLevel in (currentTargetLevel + 1) ... targetLevel {
                skillsToAdd.append((skillId: skillId, skillName: skillName, level: currentLevel))
            }
            skillLevels[skillId] = targetLevel
        }

        return skillsToAdd
    }

    // 获取前置技能（按依赖深度排序）
    private static func getAllPrerequisites(
        skillId: Int,
        requiredLevel _: Int,
        databaseManager: DatabaseManager
    ) -> [(skillId: Int, requiredLevel: Int)] {
        let requirements = SkillTreeManager.shared.getDeduplicatedSkillRequirements(
            for: skillId, databaseManager: databaseManager
        )

        // 计算每个技能的依赖深度
        var skillDepths: [Int: Int] = [:]
        for requirement in requirements {
            let depth = calculateSkillDepth(skillId: requirement.skillID, databaseManager: databaseManager)
            skillDepths[requirement.skillID] = depth
        }

        var allPrerequisites: [(skillId: Int, requiredLevel: Int)] = []
        for requirement in requirements {
            for level in 1 ... requirement.level {
                allPrerequisites.append((skillId: requirement.skillID, requiredLevel: level))
            }
        }

        // 按深度排序（深度小的先=最底层的前置优先）
        return allPrerequisites.sorted { first, second in
            let depth1 = skillDepths[first.skillId] ?? 0
            let depth2 = skillDepths[second.skillId] ?? 0

            if depth1 != depth2 {
                return depth1 < depth2 // 深度小的优先（最底层优先）
            } else if first.skillId == second.skillId {
                return first.requiredLevel < second.requiredLevel // 同一技能，等级从低到高
            } else {
                return first.skillId < second.skillId // 同深度，按 ID 排序
            }
        }
    }

    // 计算技能的依赖深度（递归）
    private static func calculateSkillDepth(skillId: Int, databaseManager: DatabaseManager) -> Int {
        let directReqs = SkillTreeManager.shared.getDeduplicatedSkillRequirements(
            for: skillId, databaseManager: databaseManager
        )

        if directReqs.isEmpty {
            return 0 // 没有前置，深度为0
        }

        // 深度 = 1 + 所有前置技能的最大深度
        let maxPrereqDepth = directReqs.map { req in
            calculateSkillDepth(skillId: req.skillID, databaseManager: databaseManager)
        }.max() ?? 0

        return 1 + maxPrereqDepth
    }

    // 获取技能名称
    private static func getSkillName(skillId: Int, databaseManager: DatabaseManager) -> String {
        let query = "SELECT name FROM types WHERE type_id = ?"
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [skillId]),
           let row = rows.first,
           let name = row["name"] as? String
        {
            return name
        }
        return "Unknown Skill (\(skillId))"
    }
}

// MARK: - 技能队列修正工具类

/// 技能队列修正工具类：补齐前置依赖、等级依赖并去重
class SkillQueueCorrector {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    /// 修正技能队列：补齐前置依赖、等级依赖并去重
    /// - Parameter inputSkills: 输入的技能ID+目标等级列表（按用户输入顺序）
    /// - Returns: 修正后的完整技能队列（包含所有前置依赖，按正确顺序排列，无重复）
    func correctSkillQueue(inputSkills: [(skillId: Int, level: Int)]) -> [(skillId: Int, level: Int)] {
        var result: [(skillId: Int, level: Int)] = []
        var addedSkills: Set<String> = [] // 用于去重，格式："skillId_level"

        Logger.debug("[队列修正] 开始修正技能队列，输入 \(inputSkills.count) 个技能")

        for (index, inputSkill) in inputSkills.enumerated() {
            Logger.debug("[队列修正] 处理第 \(index + 1) 个技能: ID \(inputSkill.skillId) 等级 \(inputSkill.level)")

            // 获取这个技能及其所有前置依赖（包括等级依赖），按正确顺序排列
            let skillsToAdd = getSkillsWithPrerequisites(skillId: inputSkill.skillId, targetLevel: inputSkill.level)

            var newCount = 0
            var skipCount = 0

            // 按顺序添加，跳过已存在的
            for skill in skillsToAdd {
                let key = "\(skill.skillId)_\(skill.level)"
                if !addedSkills.contains(key) {
                    result.append(skill)
                    addedSkills.insert(key)
                    newCount += 1
                } else {
                    skipCount += 1
                }
            }

            Logger.debug("[队列修正]   添加 \(newCount) 个技能等级，跳过 \(skipCount) 个重复")
        }

        Logger.debug("[队列修正] 修正完成，输出 \(result.count) 个技能等级")
        return result
    }

    // MARK: - Private Methods

    /// 获取技能及其所有前置依赖（包括等级依赖），按正确顺序排列
    private func getSkillsWithPrerequisites(skillId: Int, targetLevel: Int) -> [(skillId: Int, level: Int)] {
        var allSkills: [(skillId: Int, level: Int)] = []

        // 1. 获取所有前置技能依赖
        let prerequisites = getAllPrerequisitesForSkill(skillId: skillId)
        allSkills.append(contentsOf: prerequisites)

        // 2. 获取目标技能的依赖深度
        let targetSkillDepth = calculateSkillDepth(skillId: skillId)

        // 3. 添加目标技能的所有等级（从1到targetLevel）
        for level in 1 ... targetLevel {
            allSkills.append((skillId: skillId, level: level))
        }

        // 4. 重新排序：确保按深度和等级正确排列
        allSkills.sort { first, second in
            let depth1 = (first.skillId == skillId) ? targetSkillDepth : calculateSkillDepth(skillId: first.skillId)
            let depth2 = (second.skillId == skillId) ? targetSkillDepth : calculateSkillDepth(skillId: second.skillId)

            if depth1 != depth2 {
                return depth1 < depth2 // 深度小的优先（最底层的前置优先）
            } else if first.skillId == second.skillId {
                return first.level < second.level // 同一技能，等级从低到高
            } else {
                return first.skillId < second.skillId // 同深度，按 ID 排序
            }
        }

        return allSkills
    }

    /// 获取技能的所有前置要求（递归，包括所有等级）
    private func getAllPrerequisitesForSkill(skillId: Int) -> [(skillId: Int, level: Int)] {
        let requirements = SkillTreeManager.shared.getDeduplicatedSkillRequirements(
            for: skillId,
            databaseManager: databaseManager
        )

        var skillLevels: [Int: Int] = [:] // [skillId: maxLevel]

        // 收集每个技能需要的最高等级
        for requirement in requirements {
            let currentMax = skillLevels[requirement.skillID] ?? 0
            skillLevels[requirement.skillID] = max(currentMax, requirement.level)
        }

        // 计算每个技能的依赖深度
        var skillDepths: [Int: Int] = [:]
        for (prereqSkillId, _) in skillLevels {
            let depth = calculateSkillDepth(skillId: prereqSkillId)
            skillDepths[prereqSkillId] = depth
        }

        var allPrerequisites: [(skillId: Int, level: Int)] = []

        // 将每个技能展开成从1到最高等级的所有等级
        for (prereqSkillId, maxLevel) in skillLevels {
            for level in 1 ... maxLevel {
                allPrerequisites.append((skillId: prereqSkillId, level: level))
            }
        }

        // 按深度排序（深度小的先=最底层的前置优先）
        return allPrerequisites.sorted { first, second in
            let depth1 = skillDepths[first.skillId] ?? 0
            let depth2 = skillDepths[second.skillId] ?? 0

            if depth1 != depth2 {
                return depth1 < depth2
            } else if first.skillId == second.skillId {
                return first.level < second.level
            } else {
                return first.skillId < second.skillId
            }
        }
    }

    /// 计算技能的依赖深度（递归）
    private func calculateSkillDepth(skillId: Int) -> Int {
        let directReqs = SkillTreeManager.shared.getDeduplicatedSkillRequirements(
            for: skillId, databaseManager: databaseManager
        )

        if directReqs.isEmpty {
            return 0
        }

        let maxPrereqDepth = directReqs.map { req in
            calculateSkillDepth(skillId: req.skillID)
        }.max() ?? 0

        return 1 + maxPrereqDepth
    }
}

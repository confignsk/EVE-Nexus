import Foundation

/// 技能注入器计算结果
public struct InjectorCalculation {
    /// 所需大型技能注入器数量
    public let largeInjectorCount: Int
    /// 所需小型技能注入器数量
    public let smallInjectorCount: Int
    /// 总计所需技能点数
    public let totalSkillPoints: Int
}

/// 技能注入器计算工具类
public enum SkillInjectorCalculator {
    // 技能注入器类型ID
    public static let largeInjectorTypeId = 40520
    public static let smallInjectorTypeId = 45635

    // 技能点阶段定义
    private static let skillPointTiers = [
        (threshold: 0, largeValue: 500_000, smallValue: 100_000),
        (threshold: 5_000_000, largeValue: 400_000, smallValue: 80000),
        (threshold: 50_000_000, largeValue: 300_000, smallValue: 60000),
        (threshold: 80_000_000, largeValue: 150_000, smallValue: 30000),
    ]

    /// 计算完成技能队列所需的技能注入器数量
    /// - Parameters:
    ///   - requiredSkillPoints: 所需技能点数
    ///   - characterTotalSP: 角色当前总技能点数
    /// - Returns: 注入器计算结果
    public static func calculate(requiredSkillPoints: Int, characterTotalSP: Int)
        -> InjectorCalculation
    {
        let result = calculateOptimal(
            requiredSkillPoints: requiredSkillPoints, characterTotalSP: characterTotalSP
        )

        Logger.debug(
            "largeCount: \(result.largeInjectorCount), smallCount: \(result.smallInjectorCount), totalSkillPoints: \(requiredSkillPoints)"
        )

        return result
    }

    /// 使用数学计算优化的注入器计算方法
    ///
    /// 优化点：
    /// 1. 避免while循环，直接通过数学计算确定每个阶段所需的注入器数量
    /// 2. 时间复杂度从O(n)降低到O(1)，其中n是所需注入器数量
    /// 3. 正确处理5个小型注入器=1个大型注入器的成本优化规则
    ///
    /// - Parameters:
    ///   - requiredSkillPoints: 所需技能点数
    ///   - characterTotalSP: 角色当前总技能点数
    /// - Returns: 注入器计算结果
    private static func calculateOptimal(requiredSkillPoints: Int, characterTotalSP: Int)
        -> InjectorCalculation
    {
        var remainingSP = requiredSkillPoints
        var currentSP = characterTotalSP
        var largeCount = 0
        var smallCount = 0

        // 逐个技能点阶段计算大型注入器使用量（优化的数学计算）
        for i in 0 ..< skillPointTiers.count {
            guard remainingSP > 0 else { break }

            let tier = skillPointTiers[i]
            let nextThreshold =
                i < skillPointTiers.count - 1 ? skillPointTiers[i + 1].threshold : Int.max

            // 跳过已经超过的阶段
            if currentSP >= nextThreshold {
                continue
            }

            // 确定当前阶段的起始点和可用技能点空间
            let tierStartSP = max(currentSP, tier.threshold)
            let availableSPInTier = nextThreshold - tierStartSP

            if availableSPInTier <= 0 {
                continue
            }

            // 计算在当前阶段可以使用的大型注入器数量
            let maxLargeInjectorsInTier = availableSPInTier / tier.largeValue
            let neededLargeInjectorsInTier = remainingSP / tier.largeValue
            let actualLargeInjectorsInTier = min(
                maxLargeInjectorsInTier, neededLargeInjectorsInTier
            )

            if actualLargeInjectorsInTier > 0 {
                largeCount += actualLargeInjectorsInTier
                let spFromLarge = actualLargeInjectorsInTier * tier.largeValue
                remainingSP -= spFromLarge
                currentSP = tierStartSP + spFromLarge
            }
        }

        // 处理剩余技能点，使用小型注入器，并考虑5个小型注入器=1个大型注入器的规则
        if remainingSP > 0 {
            smallCount = calculateSmallInjectorsOptimal(
                remainingSP: remainingSP, startingSP: currentSP
            )

            // 检查是否可以用大型注入器替换小型注入器（5个小型注入器 = 1个大型注入器）
            if smallCount >= 5 {
                let largeInjectorSP = getInjectorSkillPoints(
                    isLarge: true, characterTotalSP: currentSP
                )

                // 如果大型注入器能满足剩余需求，优先使用大型注入器
                if largeInjectorSP >= remainingSP {
                    largeCount += 1
                    smallCount = 0
                } else {
                    // 否则重新精确计算小型注入器数量
                    smallCount = calculateSmallInjectors(
                        remainingSP: remainingSP, startingSP: currentSP
                    )
                }
            }
        }

        return InjectorCalculation(
            largeInjectorCount: largeCount,
            smallInjectorCount: smallCount,
            totalSkillPoints: requiredSkillPoints
        )
    }

    /// 优化的小型注入器计算方法（完全数学计算，无循环）
    /// - Parameters:
    ///   - remainingSP: 剩余所需技能点
    ///   - startingSP: 起始技能点
    /// - Returns: 所需小型注入器数量
    private static func calculateSmallInjectorsOptimal(remainingSP: Int, startingSP: Int) -> Int {
        var remaining = remainingSP
        var currentSP = startingSP
        var totalCount = 0

        // 遍历每个技能点阶段，直接计算所需注入器数量
        for i in 0 ..< skillPointTiers.count {
            guard remaining > 0 else { break }

            let tier = skillPointTiers[i]
            let nextThreshold =
                i < skillPointTiers.count - 1 ? skillPointTiers[i + 1].threshold : Int.max

            // 跳过已经超过的阶段
            if currentSP >= nextThreshold {
                continue
            }

            // 确定当前阶段的起始点
            let tierStartSP = max(currentSP, tier.threshold)
            let availableSPInTier = nextThreshold - tierStartSP

            if availableSPInTier <= 0 {
                continue
            }

            // 计算在当前阶段需要的技能点和注入器数量
            let neededSPInTier = min(remaining, availableSPInTier)
            let injectorsNeeded = (neededSPInTier + tier.smallValue - 1) / tier.smallValue // 向上取整

            totalCount += injectorsNeeded
            let actualSPGained = injectorsNeeded * tier.smallValue
            remaining -= actualSPGained
            currentSP = tierStartSP + actualSPGained
        }

        return totalCount
    }

    /// 精确计算所需小型注入器数量，考虑注入过程中技能点变化（保留原方法作为备用）
    /// - Parameters:
    ///   - remainingSP: 剩余所需技能点
    ///   - startingSP: 起始技能点
    /// - Returns: 所需小型注入器数量
    private static func calculateSmallInjectors(remainingSP: Int, startingSP: Int) -> Int {
        var remaining = remainingSP
        var currentSP = startingSP
        var count = 0

        while remaining > 0 {
            let injectorSP = getInjectorSkillPoints(isLarge: false, characterTotalSP: currentSP)
            count += 1

            if injectorSP >= remaining {
                break
            }

            remaining -= injectorSP
            currentSP += injectorSP
        }

        return count
    }

    /// 获取技能注入器在指定技能点数下提供的技能点数
    /// - Parameters:
    ///   - isLarge: 是否为大型技能注入器
    ///   - characterTotalSP: 角色当前总技能点数
    /// - Returns: 注入器提供的技能点数
    public static func getInjectorSkillPoints(isLarge: Bool, characterTotalSP: Int) -> Int {
        switch characterTotalSP {
        case ..<5_000_000:
            return isLarge ? 500_000 : 100_000
        case 5_000_000 ..< 50_000_000:
            return isLarge ? 400_000 : 80000
        case 50_000_000 ..< 80_000_000:
            return isLarge ? 300_000 : 60000
        default:
            return isLarge ? 150_000 : 30000
        }
    }
}

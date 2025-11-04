import Foundation

// 技能组图标管理器
class SkillGroupIconManager {
    static let shared = SkillGroupIconManager()

    private init() {}

    // 技能组图标映射
    private let skillGroupIcons: [Int: String] = [
        255: "1_42", // 射击学
        256: "1_48", // 导弹
        257: "1_26", // 飞船操控学
        258: "1_36", // 舰队支援
        266: "1_12", // 军团管理
        268: "1_25", // 生产
        269: "1_37", // 改装件
        270: "1_49", // 科学
        272: "1_24", // 电子系统
        273: "1_18", // 无人机
        274: "1_50", // 贸易学
        275: "1_05", // 导航学
        278: "1_20", // 社会学
        1209: "1_14", // 护盾
        1210: "1_03", // 装甲
        1213: "1_44", // 锁定系统
        1216: "1_30", // 工程学
        1217: "1_43", // 扫描
        1218: "1_31", // 资源处理
        1220: "1_13", // 神经增强
        1240: "1_38", // 子系统
        1241: "1_19", // 行星管理
        1545: "1_32", // 建筑管理
        4734: "1_07", // 排序
    ]

    /// 获取技能组图标名称
    /// - Parameter groupId: 技能组ID
    func getIconName(for groupId: Int) -> String {
        return skillGroupIcons[groupId] ?? "skill"
    }
}

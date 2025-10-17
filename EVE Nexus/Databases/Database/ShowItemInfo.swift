import SwiftUI

// ShowItemInfo view
struct ShowItemInfo: View {
    @ObservedObject var databaseManager: DatabaseManager
    @ObservedObject private var skillsManager = SharedSkillsManager.shared
    private let currentCharacterId: Int = {
        guard let id = UserDefaults.standard.object(forKey: "currentCharacterId") as? Int else {
            return 0
        }
        return id
    }()

    var itemID: Int
    var modifiedAttributes: [Int: Double]? // 新增：修改后的属性值

    @State private var itemDetails: ItemDetails?
    @State private var attributeGroups: [AttributeGroup] = []

    private func buildTraitsText(
        roleBonuses: [Trait], typeBonuses: [Trait], miscBonuses: [Trait] = [],
        databaseManager: DatabaseManager
    ) -> String {
        var text = ""

        // Role Bonuses
        if !roleBonuses.isEmpty {
            text += "- <b>\(NSLocalizedString("Main_Database_Role_Bonuses", comment: ""))</b>\n"
            text +=
                roleBonuses
                .map { " • \($0.content)" }
                .joined(separator: "\n")
        }

        if !roleBonuses.isEmpty && (!typeBonuses.isEmpty || !miscBonuses.isEmpty) {
            text += "\n\n"
        }

        // Type Bonuses
        if !typeBonuses.isEmpty {
            let groupedBonuses = Dictionary(grouping: typeBonuses) { $0.skill }
            let sortedSkills = groupedBonuses.keys
                .compactMap { $0 }
                .sorted()

            for skill in sortedSkills {
                if let skillName = databaseManager.getTypeName(for: skill) {
                    text +=
                        "- <a href=showinfo:\(skill)>\(skillName)</a> \(NSLocalizedString("Main_Database_Bonuses_Per_Level", comment: ""))\n"

                    let bonuses =
                        groupedBonuses[skill]?.sorted(by: { $0.importance < $1.importance }) ?? []
                    text +=
                        bonuses
                        .map { " • \($0.content)" }
                        .joined(separator: "\n")

                    if skill != sortedSkills.last {
                        text += "\n\n"
                    }
                }
            }
        }

        // 如果有Type Bonuses同时也有Misc Bonuses，添加分隔符
        if !typeBonuses.isEmpty && !miscBonuses.isEmpty {
            text += "\n\n"
        }

        // Misc Bonuses
        if !miscBonuses.isEmpty {
            text += "- <b>\(NSLocalizedString("Main_Database_Misc_Bonuses", comment: ""))</b>\n"
            text +=
                miscBonuses
                .map { $0.content.hasPrefix("<b><u>") ? "-- \($0.content)" : " • \($0.content)" }
                .joined(separator: "\n")
        }

        return text.isEmpty ? "" : text
    }

    var body: some View {
        List {
            if let itemDetails = itemDetails {
                ItemBasicInfoView(
                    itemDetails: itemDetails,
                    databaseManager: databaseManager,
                    modifiedAttributes: modifiedAttributes
                )

                // 变体 Section
                VariationsSection(
                    typeID: itemID,
                    databaseManager: databaseManager
                )

                // 属性 Sections
                AttributesView(
                    attributeGroups: attributeGroups,
                    typeID: itemID,
                    databaseManager: databaseManager
                )

                // 技能相关 Section
                if let categoryID = itemDetails.categoryID,
                   categoryID == 16
                {
                    SkillSection(
                        skillID: itemID,
                        currentCharacterId: currentCharacterId,
                        databaseManager: databaseManager
                    )
                }

                // 工业相关
                IndustrySection(
                    itemID: itemID, databaseManager: databaseManager, itemDetails: itemDetails
                )

                // 突变相关组件
                MutationSourceItemsSection(itemID: itemID, databaseManager: databaseManager)
                MutationSourceMutaplasmidsSection(itemID: itemID, databaseManager: databaseManager)
                MutationResultsSection(itemID: itemID, databaseManager: databaseManager)
                RequiredMutaplasmidsSection(itemID: itemID, databaseManager: databaseManager)
            } else {
                Text(NSLocalizedString("Item_details_notfound", comment: ""))
                    .foregroundColor(.gray)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Item_Info", comment: ""))
        .navigationBarBackButtonHidden(false)
        .onAppear {
            getItemDetails(for: itemID)
            loadAttributes(for: itemID)
        }
        .onChange(of: skillsManager.isLoading) { _, isLoading in
            // 当技能数据加载完成时，重新加载属性以更新技能等级
            if !isLoading {
                loadAttributes(for: itemID)
            }
        }
    }

    // 加载 item 详细信息
    private func getItemDetails(for itemID: Int) {
        if let itemDetail = databaseManager.getItemDetails(for: itemID) {
            // 加载 traits
            if let traitGroup = databaseManager.getTraits(for: itemID) {
                // 构建trait文本
                let traitText = buildTraitsText(
                    roleBonuses: traitGroup.roleBonuses,
                    typeBonuses: traitGroup.typeBonuses,
                    miscBonuses: traitGroup.miscBonuses,
                    databaseManager: databaseManager
                )

                // 创建新的描述文本，将trait信息拼接到原始描述后面
                let fullDescription =
                    itemDetail.description + (traitText.isEmpty ? "" : "\n\n" + traitText)

                let details = ItemDetails(
                    name: itemDetail.name,
                    en_name: itemDetail.en_name ?? "",
                    description: fullDescription,
                    iconFileName: itemDetail.iconFileName,
                    groupName: itemDetail.groupName,
                    categoryID: itemDetail.categoryID,
                    categoryName: itemDetail.categoryName,
                    typeId: itemDetail.typeId,
                    groupID: itemDetail.groupID,
                    volume: itemDetail.volume,
                    repackagedVolume: itemDetail.repackagedVolume,
                    capacity: itemDetail.capacity,
                    mass: itemDetail.mass,
                    marketGroupID: itemDetail.marketGroupID
                )
                itemDetails = details
            } else {
                itemDetails = itemDetail
            }
        }
    }

    // 加载属性
    private func loadAttributes(for itemID: Int) {
        // 先加载基础属性组
        attributeGroups = databaseManager.loadAttributeGroups(
            for: itemID,
            modifiedAttributes: modifiedAttributes
        )

        // 检查是否是技能（categoryID == 16）
        if let categoryID = itemDetails?.categoryID, categoryID == 16 {
            // 检查当前角色是否登录，如果登录则尝试获取技能等级
            if currentCharacterId != 0 {
                if let level = skillsManager.getSkillLevel(for: itemID), level >= 0 {
                    // 为技能添加或更新属性280（技能等级）
                    addOrUpdateSkillLevelAttribute(level: level)
                }
            }
        }

        // 初始化属性单位
        let units = databaseManager.loadAttributeUnits()
        AttributeDisplayConfig.initializeUnits(with: units)
    }

    // 添加或更新技能等级属性（属性ID 280）
    private func addOrUpdateSkillLevelAttribute(level: Int) {
        let skillLevelAttributeID = 280

        // 查找是否已存在属性280
        var found = false
        for (index, group) in attributeGroups.enumerated() {
            if let attrIndex = group.attributes.firstIndex(where: { $0.id == skillLevelAttributeID }) {
                // 更新现有属性值
                var updatedAttributes = group.attributes
                let updatedAttribute = updatedAttributes[attrIndex]
                updatedAttributes[attrIndex] = DogmaAttribute(
                    id: updatedAttribute.id,
                    categoryID: updatedAttribute.categoryID,
                    name: updatedAttribute.name,
                    displayName: updatedAttribute.displayName,
                    iconID: updatedAttribute.iconID,
                    iconFileName: updatedAttribute.iconFileName,
                    value: updatedAttribute.value,
                    unitID: updatedAttribute.unitID,
                    highIsGood: updatedAttribute.highIsGood,
                    modifiedValue: Double(level)
                )
                attributeGroups[index] = AttributeGroup(
                    id: group.id,
                    name: group.name,
                    attributes: updatedAttributes
                )
                found = true
                break
            }
        }

        // 如果不存在，创建新的属性280并添加到对应分类
        if !found {
            // 从数据库获取属性280的完整信息
            if let attributeInfo = databaseManager.getAttributeInfo(for: skillLevelAttributeID) {
                let newAttribute = DogmaAttribute(
                    id: skillLevelAttributeID,
                    categoryID: attributeInfo.categoryID,
                    name: attributeInfo.name,
                    displayName: attributeInfo.displayName,
                    iconID: attributeInfo.iconID,
                    iconFileName: attributeInfo.iconFileName,
                    value: 0, // 默认值
                    unitID: attributeInfo.unitID,
                    highIsGood: attributeInfo.highIsGood,
                    modifiedValue: Double(level) // 实际技能等级
                )

                // 查找对应的属性组，如果不存在则创建
                if let groupIndex = attributeGroups.firstIndex(where: { $0.id == attributeInfo.categoryID }) {
                    // 在现有组中添加属性
                    var updatedAttributes = attributeGroups[groupIndex].attributes
                    updatedAttributes.append(newAttribute)
                    updatedAttributes.sort { $0.id < $1.id }
                    attributeGroups[groupIndex] = AttributeGroup(
                        id: attributeGroups[groupIndex].id,
                        name: attributeGroups[groupIndex].name,
                        attributes: updatedAttributes
                    )
                } else {
                    // 创建新的属性组
                    let categoryName = databaseManager.getAttributeCategoryName(for: attributeInfo.categoryID) ?? "Skills"
                    let newGroup = AttributeGroup(
                        id: attributeInfo.categoryID,
                        name: categoryName,
                        attributes: [newAttribute]
                    )
                    attributeGroups.append(newGroup)
                    attributeGroups.sort { $0.id < $1.id }
                }
            }
        }
    }
}

// 用于设置特定角落圆角的扩展
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

// 自定义圆角形
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect, byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

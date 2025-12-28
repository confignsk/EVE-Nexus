import SwiftUI

// MARK: - 建筑信息行视图

struct StructureInfoRowView: View {
    let structure: MarketStructure
    let lastUpdateDate: Date?
    @ObservedObject var allianceIconLoader: AllianceIconLoader
    let systemAllianceMap: [Int: Int]
    let isLoading: Bool
    let progress: StructureOrdersProgress?

    var body: some View {
        HStack(spacing: 12) {
            // 建筑图标
            if let iconFilename = structure.iconFilename {
                IconManager.shared.loadImage(for: iconFilename)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .cornerRadius(8)
            } else {
                // 默认建筑图标
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "building.2")
                            .foregroundColor(.secondary)
                    )
            }

            // 建筑信息
            VStack(alignment: .leading, spacing: 4) {
                // 建筑名称
                Text(structure.structureName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = structure.structureName
                        } label: {
                            Label(
                                NSLocalizedString("Misc_Copy_Structure", comment: ""),
                                systemImage: "doc.on.doc"
                            )
                        }
                    }

                // 位置信息
                HStack(spacing: 4) {
                    Text(formatSystemSecurity(structure.security))
                        .foregroundColor(getSecurityColor(structure.security))
                        .font(.caption)

                    Text("\(structure.systemName) / \(structure.regionName)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }

                // 上次更新时间或加载进度
                if isLoading {
                    // 显示加载进度
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        if let progress = progress {
                            switch progress {
                            case let .loading(currentPage, totalPages):
                                Text("\(NSLocalizedString("Structure_Market_Loading", comment: "加载中")) \(currentPage)/\(totalPages)")
                                    .foregroundColor(.secondary)
                                    .font(.caption2)
                            case .completed:
                                Text(NSLocalizedString("Structure_Market_Loading", comment: "加载中"))
                                    .foregroundColor(.secondary)
                                    .font(.caption2)
                            }
                        } else {
                            Text(NSLocalizedString("Structure_Market_Loading", comment: "加载中"))
                                .foregroundColor(.secondary)
                                .font(.caption2)
                        }
                    }
                } else if let updateDate = lastUpdateDate {
                    // 显示上次更新时间（使用 TimelineView 实时更新）
                    TimelineView(.periodic(from: Date(), by: 60.0)) { timeline in
                        let minutesAgo = Int(timeline.date.timeIntervalSince(updateDate) / 60)
                        if minutesAgo >= 0 {
                            Text(formatTimeAgo(minutesAgo))
                                .foregroundColor(.secondary)
                                .font(.caption2)
                        }
                    }
                }
            }

            Spacer()

            // 建筑拥有者图标（联盟或军团）
            StructureOwnerIconView(
                structureId: Int64(structure.structureId),
                characterId: structure.characterId,
                allianceIconLoader: allianceIconLoader
            )
        }
        .padding(.vertical, 4)
    }

    // 格式化时间差为"X分钟前更新"
    private func formatTimeAgo(_ minutes: Int) -> String {
        if minutes < 1 {
            return NSLocalizedString("Structure_Market_Just_Updated", comment: "刚刚更新")
        } else {
            return String.localizedStringWithFormat(
                NSLocalizedString("Structure_Market_Minutes_Ago", comment: "%d分钟前更新"),
                minutes
            )
        }
    }
}

// MARK: - 订单统计信息行视图

struct OrdersStatisticsRowView: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundColor(.primary)

            Spacer()

            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 目录列表行视图

struct CategoryListRowView: View {
    let category: CategoryOrderData

    var body: some View {
        HStack(spacing: 12) {
            // 目录图标
            IconManager.shared.loadImage(for: category.iconFileName)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .cornerRadius(6)

            // 目录名称
            Text(category.name)
                .font(.body)
                .foregroundColor(.primary)

            Spacer()

            // 订单数
            Text("\(category.orderCount)")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }
}

// MARK: - 分组列表行视图

struct GroupListRowView: View {
    let group: GroupOrderData

    var body: some View {
        HStack(spacing: 12) {
            // 分组图标
            IconManager.shared.loadImage(for: group.iconFileName)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .cornerRadius(6)

            // 分组名称
            Text(group.name)
                .font(.body)
                .foregroundColor(.primary)

            Spacer()

            // 订单数
            Text("\(group.orderCount)")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }
}

// MARK: - 分组物品行视图

struct GroupItemRowView: View {
    let item: GroupItemInfo
    let orderType: MarketOrderType

    @State private var showStructureMarket = false
    @State private var showJitaMarket = false

    var body: some View {
        // 第一行：物品图标、名称、订单数、物品总数
        HStack(spacing: 12) {
            // 物品图标
            IconManager.shared.loadImage(for: item.iconFileName)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .cornerRadius(6)

            // 物品名称
            Text(item.name)
                .font(.body)
                .foregroundColor(.primary)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = item.name
                    } label: {
                        Label(
                            NSLocalizedString("Misc_Copy_Item_Name", comment: ""),
                            systemImage: "doc.on.doc"
                        )
                    }
                }

            Spacer()

            // 订单数和物品数
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(NSLocalizedString("Structure_Market_Orders_Count", comment: "订单数")): \(item.orderCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("\(NSLocalizedString("Structure_Market_Items_Count", comment: "物品数")): \(formatNumber(item.totalVolume))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }

        // 第二行：建筑价格（整行可点击）
        if let structurePrice = item.structurePrice {
            HStack {
                Text(orderType == .buy ? NSLocalizedString("Structure_Market_Structure_Price_Buy", comment: "当前买单") : NSLocalizedString("Structure_Market_Structure_Price_Sell", comment: "当前卖单"))
                    .font(.body)

                Spacer()

                HStack(spacing: 4) {
                    Text(formatPrice(structurePrice))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.blue)

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                showStructureMarket = true
            }
        }

        // 第三行：Jita价格（整行可点击）
        HStack {
            Text(orderType == .buy ? NSLocalizedString("Structure_Market_Jita_Price_Buy", comment: "Jita买单") : NSLocalizedString("Structure_Market_Jita_Price_Sell", comment: "Jita卖单"))
                .font(.body)

            Spacer()

            if let jitaPrice = item.jitaPrice {
                HStack(spacing: 4) {
                    Text(formatPrice(jitaPrice))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.blue)

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            } else {
                Text(NSLocalizedString("Structure_Market_No_Price", comment: "无价格"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showJitaMarket = true
        }
        .sheet(isPresented: $showStructureMarket) {
            if let structureId = item.structureId {
                NavigationStack {
                    MarketItemDetailView(
                        databaseManager: DatabaseManager.shared,
                        itemID: item.typeId,
                        selectedRegionID: -Int(structureId)
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(NSLocalizedString("Common_Done", comment: "完成")) {
                                showStructureMarket = false
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showJitaMarket) {
            NavigationStack {
                MarketItemDetailView(
                    databaseManager: DatabaseManager.shared,
                    itemID: item.typeId,
                    selectedRegionID: 10_000_002
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(NSLocalizedString("Common_Done", comment: "完成")) {
                            showJitaMarket = false
                        }
                    }
                }
            }
        }
    }

    // 格式化数字，添加千位分隔符
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    // 格式化价格，添加千位分隔符
    private func formatPrice(_ price: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: price)) ?? String(format: "%.2f", price)
    }
}

import SwiftUI

struct InAppPurchaseView: View {
    @StateObject private var iconManager = AppIconManager.shared
    @StateObject private var purchaseManager = PurchaseManager.shared
    @State private var changingIconId: String? = nil
    @State private var showingPurchaseAlert = false
    @State private var purchaseAlertMessage = ""
    @State private var selectedBadgeForPurchase: String? = nil

    // 使用统一配置
    private let iconList = AppIconConfig.iconList
    private let badgeList = AppIconConfig.badgeList
    private let selectedIconKey = AppIconConfig.selectedIconKey
    private let selectedBadgeKey = AppIconConfig.selectedBadgeKey

    // 选中的图标和角标（从保存的值初始化）
    @State private var selectedIcon: String = {
        if let savedIcon = UserDefaults.standard.string(forKey: "selectedAppIconName"),
           ["Tritanium", "TriDB", "OverseerBox", "HyperCore"].contains(savedIcon)
        {
            return savedIcon
        }
        return "Tritanium"
    }()

    @State private var selectedBadge: String = {
        if let savedBadge = UserDefaults.standard.string(forKey: "selectedAppIconBadge"),
           ["T1", "T2", "T3", "Factions", "Deadspace", "Officers"].contains(savedBadge)
        {
            return savedBadge
        }
        return "T1"
    }()

    var body: some View {
        VStack(spacing: 0) {
            // 图标选择列表
            List {
                Section {
                    ForEach(iconList, id: \.self) { iconName in
                        IconSelectionRow(
                            iconName: iconName,
                            isSelected: selectedIcon == iconName
                        ) {
                            selectedIcon = iconName
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)

            // 底部固定的角标选择
            BottomSelectionView(
                badgeList: badgeList,
                selectedBadge: $selectedBadge,
                purchaseManager: purchaseManager,
                onPurchaseRequest: { badge in
                    selectedBadgeForPurchase = badge
                    handlePurchaseRequest(for: badge)
                }
            )
        }
        .navigationTitle(NSLocalizedString("Main_In_App_Purchase", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    Task {
                        await purchaseManager.restorePurchases()
                        if let error = purchaseManager.errorMessage {
                            purchaseAlertMessage = error
                            showingPurchaseAlert = true
                        } else {
                            purchaseAlertMessage = NSLocalizedString("Purchase_Restore_Success", comment: "")
                            showingPurchaseAlert = true
                        }
                    }
                }) {
                    Text(NSLocalizedString("Purchase_Restore", comment: ""))
                }
                .disabled(purchaseManager.isLoading)
            }
        }
        .alert(isPresented: $showingPurchaseAlert) {
            Alert(
                title: Text(NSLocalizedString("Purchase_Alert_Title", comment: "")),
                message: Text(purchaseAlertMessage),
                dismissButton: .default(Text(NSLocalizedString("Purchase_Alert_OK", comment: "")))
            )
        }
        .onAppear {
            loadSavedSelection()
            // 如果产品列表为空，尝试加载（通常已在应用启动时加载）
            if purchaseManager.products.isEmpty && !purchaseManager.isLoading {
                Task {
                    await purchaseManager.loadProducts()
                }
            }
        }
        .onChange(of: selectedIcon) { _, _ in
            saveSelection()
            Task {
                await applyIconChange()
            }
        }
        .onChange(of: selectedBadge) { _, _ in
            saveSelection()
            Task {
                await applyIconChange()
            }
        }
    }

    // 根据选择的图标和角标生成图标ID
    private func getIconId() -> String? {
        return AppIconConfig.getIconId(icon: selectedIcon, badge: selectedBadge)
    }

    // 从图标ID解析图标名称和角标
    private func parseIconId(_ iconId: String?) -> (icon: String, badge: String) {
        return AppIconConfig.parseIconId(iconId)
    }

    // 加载保存的选择
    private func loadSavedSelection() {
        // 优先从 UserDefaults 读取保存的图标和角标
        if let savedIcon = UserDefaults.standard.string(forKey: selectedIconKey),
           iconList.contains(savedIcon)
        {
            selectedIcon = savedIcon
        }

        if let savedBadge = UserDefaults.standard.string(forKey: selectedBadgeKey),
           badgeList.contains(savedBadge)
        {
            selectedBadge = savedBadge
        }

        // 如果 UserDefaults 中没有保存的值，尝试从 AppIconManager 解析当前图标ID
        if UserDefaults.standard.string(forKey: selectedIconKey) == nil,
           let currentIconId = iconManager.currentIconName, !currentIconId.isEmpty
        {
            let parsed = parseIconId(currentIconId)
            selectedIcon = parsed.icon
            selectedBadge = parsed.badge
            // 保存解析后的值，以便下次直接使用
            saveSelection()
        }
    }

    // 保存当前选择
    private func saveSelection() {
        UserDefaults.standard.set(selectedIcon, forKey: selectedIconKey)
        UserDefaults.standard.set(selectedBadge, forKey: selectedBadgeKey)
    }

    private func applyIconChange() async {
        let iconId = getIconId()
        changingIconId = iconId ?? ""

        do {
            try await iconManager.setIcon(iconId)
        } catch {
            Logger.error("切换应用图标失败: \(error)")
        }

        await MainActor.run {
            changingIconId = nil
        }
    }

    // 处理购买请求
    private func handlePurchaseRequest(for badge: String) {
        guard !purchaseManager.isBadgeUnlocked(badge) else {
            // 已解锁，直接选择
            selectedBadge = badge
            return
        }

        Task {
            // 如果产品列表为空，先加载产品
            if purchaseManager.products.isEmpty {
                await purchaseManager.loadProducts()
            }

            guard let productID = purchaseManager.getProductID(for: badge),
                  let product = purchaseManager.products.first(where: { $0.id == productID })
            else {
                await MainActor.run {
                    purchaseAlertMessage = NSLocalizedString("Purchase_Product_Not_Found", comment: "")
                    showingPurchaseAlert = true
                }
                return
            }

            let success = await purchaseManager.purchase(product, for: badge)
            await MainActor.run {
                if success {
                    purchaseAlertMessage = NSLocalizedString("Purchase_Success", comment: "")
                    selectedBadge = badge
                } else if let error = purchaseManager.errorMessage {
                    purchaseAlertMessage = error
                } else {
                    purchaseAlertMessage = NSLocalizedString("Purchase_Cancelled", comment: "")
                }
                showingPurchaseAlert = true
            }
        }
    }
}

// 图标选择行
struct IconSelectionRow: View {
    let iconName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // 左侧图标
                Image(iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )

                // 右侧名称
                Text(NSLocalizedString("Icon_\(iconName)", comment: ""))
                    .foregroundColor(.primary)
                    .font(.body)

                Spacer()

                // 选中状态指示
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// 底部固定的角标选择
struct BottomSelectionView: View {
    let badgeList: [String]
    @Binding var selectedBadge: String
    @ObservedObject var purchaseManager: PurchaseManager
    let onPurchaseRequest: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            // 角标选择行
            HStack(spacing: 10) {
                ForEach(badgeList, id: \.self) { badge in
                    BadgeSelectionCell(
                        badgeName: badge,
                        isSelected: selectedBadge == badge,
                        isUnlocked: purchaseManager.isBadgeUnlocked(badge),
                        price: purchaseManager.getPriceString(for: badge),
                        isPurchasing: purchaseManager.purchasingBadge == badge
                    ) {
                        if purchaseManager.isBadgeUnlocked(badge) {
                            selectedBadge = badge
                        } else {
                            onPurchaseRequest(badge)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.primary.opacity(0.15)),
            alignment: .top
        )
        .shadow(color: Color.primary.opacity(0.2), radius: 8, x: 0, y: -4)
    }
}

// 角标选择单元格
struct BadgeSelectionCell: View {
    let badgeName: String
    let isSelected: Bool
    let isUnlocked: Bool
    let price: String?
    let isPurchasing: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(action: action) {
                ZStack {
                    if badgeName == "T1" {
                        // T1角标显示为空白圆角虚线框，中间显示减号
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                style: StrokeStyle(lineWidth: 2, dash: [5, 3])
                            )
                            .foregroundColor(isSelected ? .accentColor : .gray)

                        Image(systemName: "minus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isSelected ? .accentColor : .gray)
                    } else {
                        // 其他角标显示图标
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemBackground))
                            .shadow(color: Color.primary.opacity(0.15), radius: 3, x: 0, y: 2)

                        Image(badgeName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(6)
                            .opacity(isUnlocked ? 1.0 : 0.5)

                        // 锁定覆盖层
                        if !isUnlocked {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.3))

                            Image(systemName: "lock.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }

                    // 选中状态边框
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.accentColor, lineWidth: 2.5)
                    }

                    // 加载指示器（仅显示在正在购买的角标上）
                    if isPurchasing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .frame(width: 50, height: 50)
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())
            .disabled(isPurchasing)

            // 价格/状态标签
            if isUnlocked {
                Text(NSLocalizedString("Purchase_Badge_Unlocked", comment: ""))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            } else if let price = price {
                Text(price)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(price == NSLocalizedString("Purchase_Price_Loading", comment: "") ? .secondary : .secondary)
            }
        }
    }
}

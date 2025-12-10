import Foundation
import StoreKit

@MainActor
class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    @Published var purchasedRanks: Set<Int> = []
    @Published var products: [Product] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var purchasingBadge: String? = nil // 正在购买的角标

    // 产品ID定义
    private let productIDs: [String: Int] = [
        "com.evenexus.badge.rank2": 2, // T2
        "com.evenexus.badge.rank3": 3, // T3
        "com.evenexus.badge.rank_faction": 4, // Factions
        "com.evenexus.badge.rank_deadspace": 5, // Deadspace
        "com.evenexus.badge.rank_officer": 6, // Officers
    ]

    // 角标到rank的映射
    let badgeToRank: [String: Int] = [
        "T1": 1,
        "T2": 2,
        "T3": 3,
        "Factions": 4,
        "Deadspace": 5,
        "Officers": 6,
    ]

    // rank到角标的映射
    let rankToBadge: [Int: String] = [
        1: "T1",
        2: "T2",
        3: "T3",
        4: "Factions",
        5: "Deadspace",
        6: "Officers",
    ]

    private let purchasedRanksKey = "purchasedBadgeRanks"

    private init() {
        loadPurchasedRanks()
        // rank1 (T1) 默认解锁
        purchasedRanks.insert(1)

        // 在后台检查已购买的产品
        Task {
            await checkPurchasedProducts()
        }

        // 监听交易更新
        Task {
            await listenForTransactions()
        }
    }

    // 检查已购买的产品
    private func checkPurchasedProducts() async {
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                // 根据产品ID找到对应的rank
                if let rank = productIDs[transaction.productID] {
                    purchasedRanks.insert(rank)
                    Logger.info("[+] 检测到已购买: rank\(rank)")
                }
            } catch {
                Logger.error("[x] 验证交易失败: \(error)")
            }
        }

        savePurchasedRanks()
    }

    // 监听交易更新
    private func listenForTransactions() async {
        for await result in Transaction.updates {
            do {
                let transaction = try checkVerified(result)

                // 根据产品ID找到对应的rank
                if let rank = productIDs[transaction.productID] {
                    purchasedRanks.insert(rank)
                    savePurchasedRanks()
                    Logger.info("[+] 检测到新的购买交易: rank\(rank)")
                }

                await transaction.finish()
            } catch {
                Logger.error("[x] 验证交易更新失败: \(error)")
            }
        }
    }

    // 加载已购买的rank
    private func loadPurchasedRanks() {
        if let data = UserDefaults.standard.data(forKey: purchasedRanksKey),
           let ranks = try? JSONDecoder().decode(Set<Int>.self, from: data)
        {
            purchasedRanks = ranks
        }
        // 确保rank1始终解锁
        purchasedRanks.insert(1)
    }

    // 保存已购买的rank
    private func savePurchasedRanks() {
        if let data = try? JSONEncoder().encode(purchasedRanks) {
            UserDefaults.standard.set(data, forKey: purchasedRanksKey)
        }
    }

    // 检查角标是否已解锁
    func isBadgeUnlocked(_ badge: String) -> Bool {
        guard let rank = badgeToRank[badge] else { return false }
        return purchasedRanks.contains(rank)
    }

    // 检查rank是否已解锁
    func isRankUnlocked(_ rank: Int) -> Bool {
        return purchasedRanks.contains(rank)
    }

    // 获取角标对应的产品ID
    func getProductID(for badge: String) -> String? {
        guard let rank = badgeToRank[badge], rank > 1 else { return nil }
        return productIDs.first(where: { $0.value == rank })?.key
    }

    // 获取rank对应的产品ID
    func getProductID(for rank: Int) -> String? {
        guard rank > 1 else { return nil }
        return productIDs.first(where: { $0.value == rank })?.key
    }

    // 加载产品信息
    func loadProducts() async {
        isLoading = true
        errorMessage = nil

        do {
            let productIdentifiers = Array(productIDs.keys)
            products = try await Product.products(for: productIdentifiers)
            Logger.info("[+] 成功加载 \(products.count) 个内购产品")
        } catch {
            errorMessage = error.localizedDescription
            Logger.error("[x] 加载内购产品失败: \(error)")
        }

        isLoading = false
    }

    // 购买产品
    func purchase(_ product: Product, for badge: String) async -> Bool {
        isLoading = true
        purchasingBadge = badge
        errorMessage = nil

        do {
            let result = try await product.purchase()

            switch result {
            case let .success(verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()

                // 解锁对应的rank
                if let rank = productIDs[product.id] {
                    purchasedRanks.insert(rank)
                    savePurchasedRanks()
                    Logger.info("[+] 成功购买并解锁 rank\(rank)")
                }

                isLoading = false
                purchasingBadge = nil
                return true

            case .userCancelled:
                Logger.info("[-] 用户取消购买")
                isLoading = false
                purchasingBadge = nil
                return false

            case .pending:
                Logger.info("[!] 购买待处理")
                isLoading = false
                purchasingBadge = nil
                return false

            @unknown default:
                Logger.info("[-] 未知购买状态")
                isLoading = false
                purchasingBadge = nil
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            Logger.error("[x] 购买失败: \(error)")
            isLoading = false
            purchasingBadge = nil
            return false
        }
    }

    // 恢复购买
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil

        do {
            try await AppStore.sync()

            // 检查所有交易
            for await result in Transaction.currentEntitlements {
                do {
                    let transaction = try checkVerified(result)

                    // 根据产品ID找到对应的rank
                    if let rank = productIDs[transaction.productID] {
                        purchasedRanks.insert(rank)
                        Logger.info("[+] 恢复购买: rank\(rank)")
                    }
                } catch {
                    Logger.error("[x] 验证交易失败: \(error)")
                }
            }

            savePurchasedRanks()
            Logger.info("[+] 恢复购买完成")
        } catch {
            errorMessage = error.localizedDescription
            Logger.error("[x] 恢复购买失败: \(error)")
        }

        isLoading = false
    }

    // 验证交易
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw PurchaseError.unverifiedTransaction
        case let .verified(safe):
            return safe
        }
    }

    // 获取产品价格字符串
    func getPriceString(for badge: String) -> String? {
        guard let rank = badgeToRank[badge] else {
            return nil
        }

        // T1 (rank1) 是免费的
        if rank == 1 {
            return NSLocalizedString("Purchase_Price_Free", comment: "")
        }

        // 如果正在加载且产品列表为空，返回占位符
        if isLoading, products.isEmpty {
            return NSLocalizedString("Purchase_Price_Loading", comment: "")
        }

        // 其他角标需要从产品中获取价格
        guard let productID = getProductID(for: rank) else {
            return nil
        }

        // 如果产品列表为空（但不在加载中），返回占位符
        if products.isEmpty {
            return NSLocalizedString("Purchase_Price_Loading", comment: "")
        }

        // 查找产品
        if let product = products.first(where: { $0.id == productID }) {
            return product.displayPrice
        }

        // 如果找不到产品，返回占位符（可能还在加载）
        return NSLocalizedString("Purchase_Price_Loading", comment: "")
    }
}

enum PurchaseError: Error {
    case unverifiedTransaction
}

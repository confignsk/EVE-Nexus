import Foundation

struct LPStoreOffer: Codable {
    let akCost: Int
    let iskCost: Int
    let lpCost: Int
    let offerId: Int
    let quantity: Int
    let requiredItems: [RequiredItem]
    let typeId: Int

    enum CodingKeys: String, CodingKey {
        case akCost = "ak_cost"
        case iskCost = "isk_cost"
        case lpCost = "lp_cost"
        case offerId = "offer_id"
        case quantity
        case requiredItems = "required_items"
        case typeId = "type_id"
    }
}

struct RequiredItem: Codable {
    let quantity: Int
    let typeId: Int

    enum CodingKeys: String, CodingKey {
        case quantity
        case typeId = "type_id"
    }
}

// MARK: - LP商店API

@globalActor actor LPStoreAPIActor {
    static let shared = LPStoreAPIActor()
}

@LPStoreAPIActor
class LPStoreAPI {
    static let shared = LPStoreAPI()

    private init() {}

    // MARK: - 公共方法

    /// 获取单个军团的LP商店兑换列表
    /// - Parameters:
    ///   - corporationId: 军团ID
    /// - Returns: LP商店兑换列表
    func fetchCorporationLPStoreOffers(corporationId: Int) async throws -> [LPStoreOffer] {
        // 直接从 SDE 数据库读取数据
        return try await loadFromSDEDatabase(corporationId: corporationId)
    }

    // MARK: - 私有方法

    /// 从 SDE 数据库加载单个军团的 LP 商店数据
    private func loadFromSDEDatabase(corporationId: Int) async throws -> [LPStoreOffer] {
        let query = """
            SELECT 
                lo.offer_id,
                loo.type_id,
                loo.quantity,
                loo.isk_cost,
                loo.lp_cost,
                loo.ak_cost
            FROM loyalty_offers lo
            JOIN loyalty_offer_outputs loo ON lo.offer_id = loo.offer_id
            WHERE lo.corporation_id = ?
            ORDER BY lo.offer_id
        """

        guard case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: [corporationId]) else {
            Logger.error("[x] 从SDE数据库查询LP商店数据失败 - 军团ID: \(corporationId)")
            return []
        }

        if rows.isEmpty {
            return []
        }

        // 收集所有 offer_id
        let offerIds = Set(rows.compactMap { $0["offer_id"] as? Int })

        // 查询所有 required items
        var requiredItemsMap: [Int: [RequiredItem]] = [:]
        if !offerIds.isEmpty {
            let reqQuery = """
                SELECT offer_id, required_type_id, required_quantity
                FROM loyalty_offer_requirements
                WHERE offer_id IN (\(offerIds.sorted().map { String($0) }.joined(separator: ",")))
            """

            if case let .success(reqRows) = DatabaseManager.shared.executeQuery(reqQuery) {
                for row in reqRows {
                    guard let offerId = row["offer_id"] as? Int,
                          let typeId = row["required_type_id"] as? Int,
                          let quantity = row["required_quantity"] as? Int
                    else {
                        continue
                    }

                    let requiredItem = RequiredItem(quantity: quantity, typeId: typeId)
                    requiredItemsMap[offerId, default: []].append(requiredItem)
                }
            }
        }

        // 构建 LPStoreOffer 数组
        var offers: [LPStoreOffer] = []
        for row in rows {
            guard let offerId = row["offer_id"] as? Int,
                  let typeId = row["type_id"] as? Int,
                  let quantity = row["quantity"] as? Int,
                  let iskCost = row["isk_cost"] as? Int,
                  let lpCost = row["lp_cost"] as? Int,
                  let akCost = row["ak_cost"] as? Int
            else {
                continue
            }

            let requiredItems = requiredItemsMap[offerId] ?? []
            let offer = LPStoreOffer(
                akCost: akCost,
                iskCost: iskCost,
                lpCost: lpCost,
                offerId: offerId,
                quantity: quantity,
                requiredItems: requiredItems,
                typeId: typeId
            )
            offers.append(offer)
        }

        return offers
    }
}

import Foundation
import SwiftUI

struct CorporationLoyaltyInfo: Identifiable {
    let id: Int
    let corporationId: Int
    let loyaltyPoints: Int
    let corporationName: String
    let enName: String
    let zhName: String
    let iconFileName: String
    let militiaFaction: Int?

    var isMilitia: Bool {
        if let militia = militiaFaction, militia > 0 {
            return true
        }
        return false
    }
}

@MainActor
class CharacterLoyaltyPointsViewModel: ObservableObject {
    @Published var loyaltyPoints: [CorporationLoyaltyInfo] = []
    @Published var isLoading = false
    @Published var error: Error?

    private var hasLoadedData = false

    func fetchLoyaltyPoints(characterId: Int, forceRefresh: Bool = false) {
        if hasLoadedData, !forceRefresh {
            return
        }

        isLoading = true
        error = nil

        Task {
            await loadLoyaltyPoints(characterId: characterId, forceRefresh: forceRefresh)
        }
    }

    func refreshLoyaltyPoints(characterId: Int) async {
        isLoading = true
        error = nil
        await loadLoyaltyPoints(characterId: characterId, forceRefresh: true)
    }

    private func loadLoyaltyPoints(characterId: Int, forceRefresh: Bool) async {
        do {
            let points = try await CharacterLoyaltyPointsAPI.shared.fetchLoyaltyPoints(
                characterId: characterId, forceRefresh: forceRefresh
            )
            var corporationInfo: [CorporationLoyaltyInfo] = []

            for point in points {
                if let corpInfo = try await getCorporationInfo(corporationId: point.corporation_id) {
                    corporationInfo.append(
                        CorporationLoyaltyInfo(
                            id: point.corporation_id,
                            corporationId: point.corporation_id,
                            loyaltyPoints: point.loyalty_points,
                            corporationName: corpInfo.name,
                            enName: corpInfo.enName,
                            zhName: corpInfo.zhName,
                            iconFileName: corpInfo.iconFileName,
                            militiaFaction: corpInfo.militiaFaction
                        ))
                }
            }

            loyaltyPoints = corporationInfo.sorted(by: { $0.corporationId < $1.corporationId })
            hasLoadedData = true
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }

    private func getCorporationInfo(corporationId: Int) async throws -> (
        name: String, enName: String, zhName: String, iconFileName: String, militiaFaction: Int?
    )? {
        let query = """
            SELECT name, en_name, zh_name, icon_filename, militia_faction FROM npcCorporations WHERE corporation_id = \(corporationId)
        """

        guard case let .success(rows) = SQLiteManager.shared.executeQuery(query),
              let result = rows.first,
              let name = result["name"] as? String,
              let enName = result["en_name"] as? String,
              let zhName = result["zh_name"] as? String,
              let iconFileName = result["icon_filename"] as? String
        else {
            return nil
        }
        let militiaFaction = result["militia_faction"] as? Int
        return (name, enName, zhName, iconFileName, militiaFaction)
    }
}

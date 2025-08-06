import Foundation

// MARK: - 共享数据模型
struct Center: Codable {
    let x: Double
    let y: Double
}

// MARK: - 全星域地图数据结构 (regions_data.json)
struct RegionData: Codable {
    let region_id: Int
    let faction_id: Int
    let center: Center
    let relations: [String]
}

// MARK: - 星域地图数据结构 (systems_data.json 中的单个星域数据)
struct SystemMapData: Codable {
    let region_id: Int
    let faction_id: Int
    let center: Center
    let relations: [String]
    let systems: [String: SystemPosition]
    let jumps: [String: [String]]
}

struct SystemPosition: Codable {
    let x: Double
    let y: Double
}

struct SystemNodeData {
    let systemId: Int
    let name: String
    let nameEn: String
    let nameZh: String
    let security: Double
    let regionId: Int
    let position: CGPoint
    let connections: [Int]
    let planetCounts: PlanetCounts
}

struct PlanetCounts {
    let gas: Int
    let temperate: Int
    let barren: Int
    let oceanic: Int
    let ice: Int
    let lava: Int
    let storm: Int
    let plasma: Int
    let jove: Int
    
    init(gas: Int = 0, temperate: Int = 0, barren: Int = 0, oceanic: Int = 0, 
         ice: Int = 0, lava: Int = 0, storm: Int = 0, plasma: Int = 0, jove: Int = 0) {
        self.gas = gas
        self.temperate = temperate
        self.barren = barren
        self.oceanic = oceanic
        self.ice = ice
        self.lava = lava
        self.storm = storm
        self.plasma = plasma
        self.jove = jove
    }
    
    func getCount(for filter: RegionSystemMapView.PlanetFilter) -> Int {
        switch filter {
        case .all:
            return gas + temperate + barren + oceanic + ice + lava + storm + plasma + jove
        case .gas:
            return gas
        case .temperate:
            return temperate
        case .barren:
            return barren
        case .oceanic:
            return oceanic
        case .ice:
            return ice
        case .lava:
            return lava
        case .storm:
            return storm
        case .plasma:
            return plasma
        case .jove:
            return jove
        }
    }
}

struct StarMapRegion: Identifiable {
    let id: Int
    let name: String
    let nameEn: String
    let nameZh: String
}

// MARK: - 导航枚举
enum RegionNavigation: Hashable {
    case regionMap(Int, String) // regionId, regionName
} 